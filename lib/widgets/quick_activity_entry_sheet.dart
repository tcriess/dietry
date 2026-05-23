import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/activity_item.dart';
import '../models/activity_shortcut.dart';
import '../models/physical_activity.dart';
import '../services/activity_database_service.dart';
import '../services/activity_shortcuts_service.dart';
import '../services/neon_database_service.dart';
import '../services/physical_activity_service.dart';
import '../services/user_body_measurements_service.dart';
import '../l10n/app_localizations.dart';

/// Unified bottom sheet for adding a [PhysicalActivity] — the single entry
/// point on the activities tab.
///
/// Contents:
///   • Search    — live ActivityDatabaseService.searchActivities
///   • Recent    — past activities, weekday-recurrence + hour-distance ranked
///   • Favorites — ActivityItem.isFavourite rows
///   • Shortcuts — device-local SharedPreferences shortcuts
///   • Buttons   — Manual Entry (full form) and Health Connect import
class QuickActivityEntrySheet extends StatefulWidget {
  final NeonDatabaseService dbService;

  /// The day the user is currently viewing. New entries default their
  /// startTime to the *current* clock time *on that day* — so back-filling
  /// yesterday still produces "today's lunch run" semantics for the user.
  final DateTime date;

  /// Persist a fully-built [PhysicalActivity]. Caller owns the SyncService
  /// / DataStore wiring.
  final Future<void> Function(PhysicalActivity) onAdd;

  /// Opens the full manual-entry form (`AddActivityScreen`).
  final VoidCallback onManualEntry;

  /// Triggers Health Connect import. Null when the platform doesn't
  /// support Health Connect (web/desktop) — the button is hidden.
  final VoidCallback? onImportHealthConnect;

  /// Opens the activity-database management screen (edit / delete custom
  /// templates). Null hides the header button — e.g. in guest mode where
  /// there's no remote database to manage.
  final VoidCallback? onManageDatabase;

  const QuickActivityEntrySheet({
    super.key,
    required this.dbService,
    required this.date,
    required this.onAdd,
    required this.onManualEntry,
    this.onImportHealthConnect,
    this.onManageDatabase,
  });

  @override
  State<QuickActivityEntrySheet> createState() =>
      _QuickActivityEntrySheetState();
}

class _QuickActivityEntrySheetState extends State<QuickActivityEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Raw past activities, last 90 days, ordered by start_time desc. Kept
  /// raw so the recurrence-aware ranking in [_displayRecent] re-evaluates
  /// on each rebuild without a network round-trip.
  List<PhysicalActivity> _rawRecent = [];
  List<ActivityItem> _favourites = [];
  List<ActivityShortcut> _shortcuts = [];
  Map<String, ActivityItem> _recentActivityCache = {};
  _ActivityRecurrenceIndex? _recurrence;
  bool _loading = true;
  String? _addingId;

  /// User body weight, used to estimate calories from MET when an
  /// [ActivityItem] (favourite or search hit) has no stored kcal.
  double? _userWeightKg;

  String? _lastAddedName;
  Timer? _toastTimer;

  // ── Live search ──────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<ActivityItem> _searchResults = [];
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadRecent(),
      _loadFavourites(),
      _loadShortcuts(),
      _loadWeight(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRecent() async {
    final db = widget.dbService;
    final tokenValid = await db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) return;
    final userId = db.userId;
    if (userId == null) return;

    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 90));

    try {
      final svc = PhysicalActivityService(db);
      final entries =
          await svc.getActivitiesInRange(start: start, end: end);

      // Preload ActivityItems for entries that link to activity_database —
      // lets the long-press "adjust" path reuse MET / category metadata.
      final actSvc = ActivityDatabaseService(db);
      final displayed = _rankAndDedupRecent(entries, DateTime.now().hour);
      final ids = displayed
          .where((e) => e.activityId != null)
          .map((e) => e.activityId!)
          .toSet();
      final cache = <String, ActivityItem>{};
      for (final id in ids) {
        final item = await actSvc.getActivityById(id);
        if (item != null) cache[id] = item;
      }

      final recurrence = _ActivityRecurrenceIndex.build(entries);

      if (mounted) {
        setState(() {
          _rawRecent = entries;
          _recentActivityCache = cache;
          _recurrence = recurrence;
        });
      }
    } catch (_) {
      // Best-effort: an empty Recent is acceptable.
    }
  }

  List<PhysicalActivity> _displayRecent() => _rankAndDedupRecent(
        _rawRecent,
        DateTime.now().hour,
        _recurrence,
        widget.date.weekday,
      );

  Future<void> _loadFavourites() async {
    try {
      final favs = await ActivityDatabaseService(widget.dbService)
          .getFavouriteActivities();
      if (mounted) setState(() => _favourites = favs);
    } catch (_) {}
  }

  Future<void> _loadShortcuts() async {
    final list = await ActivityShortcutsService.loadShortcuts();
    if (mounted) setState(() => _shortcuts = list);
  }

  Future<void> _loadWeight() async {
    try {
      final m = await UserBodyMeasurementsService(widget.dbService)
          .getCurrentMeasurement();
      if (mounted) setState(() => _userWeightKg = m?.weight);
    } catch (_) {
      // Weight is optional — favourites/search will skip the calorie
      // estimate and the user can fill it in via the manual form later.
    }
  }

  // ── search ───────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _searching = true;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (q.isEmpty) return;
    try {
      final results = await ActivityDatabaseService(widget.dbService)
          .searchActivities(q, limit: 40);
      if (!mounted || q != _query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _searchResults = [];
      _searching = false;
    });
  }

  // ── add helpers ──────────────────────────────────────────────────────────

  Future<void> _addEntry(PhysicalActivity entry, String displayName) async {
    if (_addingId != null) return;
    final tempId = entry.id ?? const Uuid().v4();
    setState(() => _addingId = tempId);
    try {
      await widget.onAdd(entry);
      if (mounted) {
        HapticFeedback.lightImpact();
        _toastTimer?.cancel();
        setState(() => _lastAddedName = displayName);
        _toastTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _lastAddedName = null);
        });
      }
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  /// Builds a [PhysicalActivity] whose startTime is "now on [widget.date]" so
  /// back-filling a past day still produces an entry at the user's current
  /// clock time on that day.
  PhysicalActivity _buildEntry({
    required ActivityType activityType,
    required String? activityId,
    required String? activityName,
    required int durationMinutes,
    double? caloriesBurned,
    double? distanceKm,
    String? notes,
  }) {
    final now = TimeOfDay.now();
    final start = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      now.hour,
      now.minute,
    );
    final end = start.add(Duration(minutes: durationMinutes));
    return PhysicalActivity(
      activityType: activityType,
      activityId: activityId,
      activityName: activityName,
      startTime: start,
      endTime: end,
      durationMinutes: durationMinutes,
      caloriesBurned: caloriesBurned,
      distanceKm: distanceKm,
      notes: notes,
      source: DataSource.manual,
    );
  }

  Future<void> _instantAddRecent(PhysicalActivity recent) async {
    final entry = _buildEntry(
      activityType: recent.activityType,
      activityId: recent.activityId,
      activityName: recent.activityName,
      durationMinutes:
          recent.durationMinutes ?? recent.calculatedDuration,
      caloriesBurned: recent.caloriesBurned,
      distanceKm: recent.distanceKm,
      notes: recent.notes,
    );
    await _addEntry(entry, recent.displayName);
  }

  Future<void> _adjustRecent(PhysicalActivity recent) async {
    final item = recent.activityId != null
        ? _recentActivityCache[recent.activityId]
        : null;
    final result = await _confirm(
      title: recent.displayName,
      activityType: recent.activityType,
      activityId: recent.activityId,
      activityName: recent.activityName,
      initialDuration: recent.durationMinutes ?? recent.calculatedDuration,
      initialCalories: recent.caloriesBurned,
      distanceKm: recent.distanceKm,
      metForEstimate: item?.metValue ?? recent.activityType.metValue,
    );
    if (result != null) await _addEntry(result.entry, result.displayName);
  }

  Future<void> _pickFavourite(ActivityItem item) async {
    final type = _activityTypeForItem(item);
    final result = await _confirm(
      title: item.name,
      activityType: type,
      activityId: item.id,
      activityName: item.name,
      initialDuration: 30,
      metForEstimate: item.metValue,
    );
    if (result != null) await _addEntry(result.entry, result.displayName);
  }

  Future<void> _pickSearchResult(ActivityItem item) => _pickFavourite(item);

  Future<void> _instantAddShortcut(ActivityShortcut sc) async {
    final type = ActivityType.values.firstWhere(
      (t) => t.name == sc.activityType,
      orElse: () => ActivityType.other,
    );
    final entry = _buildEntry(
      activityType: type,
      activityId: sc.activityId,
      activityName: sc.label,
      durationMinutes: sc.durationMinutes,
      caloriesBurned: sc.caloriesBurned,
      distanceKm: sc.distanceKm,
      notes: sc.notes,
    );
    await _addEntry(entry, sc.label);
  }

  ActivityType _activityTypeForItem(ActivityItem item) {
    // ActivityItem doesn't store an enum directly — best-effort match by
    // category, fall back to "other" so the enum is never wrong, just
    // generic.
    final cat = item.category?.toLowerCase();
    switch (cat) {
      case 'ausdauer':
      case 'cardio':
        return ActivityType.running;
      case 'kraft':
      case 'strength':
        return ActivityType.weightTraining;
      default:
        return ActivityType.other;
    }
  }

  // ── confirm dialog ───────────────────────────────────────────────────────

  Future<({PhysicalActivity entry, String displayName})?> _confirm({
    required String title,
    required ActivityType activityType,
    required String? activityId,
    required String? activityName,
    required int initialDuration,
    double? initialCalories,
    double? distanceKm,
    required double metForEstimate,
  }) {
    return showDialog<({PhysicalActivity entry, String displayName})>(
      context: context,
      builder: (ctx) => _ConfirmActivityDialog(
        title: title,
        activityType: activityType,
        activityId: activityId,
        activityName: activityName,
        initialDuration: initialDuration,
        initialCalories: initialCalories,
        distanceKm: distanceKm,
        metForEstimate: metForEstimate,
        userWeightKg: _userWeightKg,
        date: widget.date,
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.directions_run, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.addActivity,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (widget.onManageDatabase != null)
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: l.myActivities,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onManageDatabase!();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _lastAddedName == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _ActivityAddedToast(name: _lastAddedName!),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l.searchActivityHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l.clearSearch,
                      visualDensity: VisualDensity.compact,
                      onPressed: _clearSearch,
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _query.isEmpty ? _buildBrowse() : _buildSearchResults(),
        ),
      ],
    );
  }

  Widget _buildBrowse() {
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              if (widget.onImportHealthConnect != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.health_and_safety_outlined,
                        size: 18),
                    label: Text(l.importHealthConnect,
                        style: const TextStyle(fontSize: 13)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onImportHealthConnect!();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(l.manualEntry,
                      style: const TextStyle(fontSize: 13)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onManualEntry();
                  },
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabRecent),
            Tab(text: l.tabFavorites),
            Tab(text: l.tabShortcuts),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RecentActivityTab(
                entries: _displayRecent(),
                recurrence: _recurrence,
                weekday: widget.date.weekday,
                addingId: _addingId,
                onTap: _instantAddRecent,
                onLongPress: _adjustRecent,
              ),
              _FavouriteActivityTab(
                items: _favourites,
                addingId: _addingId,
                onTap: _pickFavourite,
              ),
              _ActivityShortcutsTab(
                shortcuts: _shortcuts,
                addingId: _addingId,
                onTap: _instantAddShortcut,
                onDelete: (sc) async {
                  await ActivityShortcutsService.removeShortcut(sc.id);
                  await _loadShortcuts();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final l = AppLocalizations.of(context)!;
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.noSearchResults(_query),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final item = _searchResults[i];
        final isAdding = _addingId == item.id;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            child: const Icon(Icons.fitness_center,
                color: Colors.blue, size: 20),
          ),
          title: Text(item.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            'MET ${item.metValue.toStringAsFixed(1)}'
            '${item.category != null ? ' · ${item.category}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, color: Colors.teal),
          onTap: isAdding ? null : () => _pickSearchResult(item),
        );
      },
    );
  }
}

// ── Recent ranking ────────────────────────────────────────────────────────────

const int _activityRecurrenceThreshold = 4;

int _hourDistance(int a, int b) {
  final d = (a - b).abs();
  return d > 12 ? 24 - d : d;
}

/// Lower is better. Sort order: recurrence (count ≥ threshold wins, higher
/// counts beat lower within the group) → hour-of-day distance → recency.
/// No meal-type analog — activities don't have a "current meal" context.
int _compareRecent(
  PhysicalActivity a,
  PhysicalActivity b,
  int hour,
  _ActivityRecurrenceIndex? rec,
  int weekday,
) {
  if (rec != null) {
    final aRec = rec.count(a.displayName, weekday);
    final bRec = rec.count(b.displayName, weekday);
    final aIsRec = aRec >= _activityRecurrenceThreshold;
    final bIsRec = bRec >= _activityRecurrenceThreshold;
    if (aIsRec != bIsRec) return aIsRec ? -1 : 1;
    if (aIsRec && bIsRec && aRec != bRec) return bRec - aRec;
  }

  final aHour = _hourDistance(a.startTime.hour, hour);
  final bHour = _hourDistance(b.startTime.hour, hour);
  if (aHour != bHour) return aHour - bHour;

  return b.startTime.compareTo(a.startTime);
}

List<PhysicalActivity> _rankAndDedupRecent(
  List<PhysicalActivity> entries,
  int hour, [
  _ActivityRecurrenceIndex? recurrence,
  int weekday = 0,
]) {
  final sorted = entries.toList()
    ..sort((a, b) => _compareRecent(a, b, hour, recurrence, weekday));
  final seen = <String>{};
  final result = <PhysicalActivity>[];
  for (final e in sorted) {
    if (seen.add(e.displayName.toLowerCase().trim()) && result.length < 30) {
      result.add(e);
    }
  }
  return result;
}

// ── Recurrence index ──────────────────────────────────────────────────────────

class _ActivityRecurrenceIndex {
  /// `"$displayName|$weekday"` → distinct dates the activity appeared on.
  final Map<String, int> _counts;

  _ActivityRecurrenceIndex._(this._counts);

  factory _ActivityRecurrenceIndex.build(List<PhysicalActivity> entries) {
    final seenTriple = <String>{};
    final counts = <String, int>{};
    for (final e in entries) {
      final name = e.displayName.toLowerCase().trim();
      if (name.isEmpty) continue;
      final dateStr = e.startTime.toIso8601String().split('T')[0];
      final triple = '$dateStr|$name';
      if (!seenTriple.add(triple)) continue;
      final key = '$name|${e.startTime.weekday}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return _ActivityRecurrenceIndex._(counts);
  }

  int count(String displayName, int weekday) =>
      _counts['${displayName.toLowerCase().trim()}|$weekday'] ?? 0;
}

// ── Tabs ──────────────────────────────────────────────────────────────────────

class _RecentActivityTab extends StatelessWidget {
  final List<PhysicalActivity> entries;
  final _ActivityRecurrenceIndex? recurrence;
  final int weekday;
  final String? addingId;
  final void Function(PhysicalActivity) onTap;
  final void Function(PhysicalActivity) onLongPress;

  const _RecentActivityTab({
    required this.entries,
    required this.recurrence,
    required this.weekday,
    required this.addingId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (entries.isEmpty) {
      return Center(
        child: Text(l.noRecentActivities,
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.orange.shade50,
          child: Text(
            l.recentTapHint,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: entries.length,
            itemBuilder: (ctx, i) {
              final e = entries[i];
              final isAdding = addingId == e.id;
              final duration =
                  e.durationMinutes ?? e.calculatedDuration;
              final kcal = e.caloriesBurned;
              final isRecurrent = recurrence != null &&
                  recurrence!.count(e.displayName, weekday) >=
                      _activityRecurrenceThreshold;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: e.activityType.color.withValues(alpha: 0.12),
                  child: Icon(e.activityType.icon,
                      color: e.activityType.color, size: 20),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(e.displayName,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isRecurrent) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.repeat,
                          size: 13, color: Colors.deepPurple),
                    ],
                  ],
                ),
                subtitle: Text(
                  '$duration min'
                  '${kcal != null ? ' · ${kcal.toStringAsFixed(0)} kcal' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: isAdding
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline,
                        color: Colors.teal),
                onTap: isAdding ? null : () => onTap(e),
                onLongPress: isAdding ? null : () => onLongPress(e),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FavouriteActivityTab extends StatelessWidget {
  final List<ActivityItem> items;
  final String? addingId;
  final void Function(ActivityItem) onTap;

  const _FavouriteActivityTab({
    required this.items,
    required this.addingId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.noFavoriteActivities,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isAdding = addingId == item.id;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.amber.shade50,
            child: const Icon(Icons.star, color: Colors.amber, size: 20),
          ),
          title: Text(item.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            'MET ${item.metValue.toStringAsFixed(1)}'
            '${item.category != null ? ' · ${item.category}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, color: Colors.teal),
          onTap: isAdding ? null : () => onTap(item),
        );
      },
    );
  }
}

class _ActivityShortcutsTab extends StatelessWidget {
  final List<ActivityShortcut> shortcuts;
  final String? addingId;
  final void Function(ActivityShortcut) onTap;
  final void Function(ActivityShortcut) onDelete;

  const _ActivityShortcutsTab({
    required this.shortcuts,
    required this.addingId,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (shortcuts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.noActivityShortcuts,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: shortcuts.length,
      itemBuilder: (ctx, i) {
        final sc = shortcuts[i];
        final isAdding = addingId == sc.id;
        return Dismissible(
          key: Key(sc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => onDelete(sc),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE0F2F1),
              child: Icon(Icons.bolt, color: Colors.teal, size: 20),
            ),
            title: Text(sc.label, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              '${sc.durationMinutes} min'
              '${sc.caloriesBurned != null ? ' · ${sc.caloriesBurned!.toStringAsFixed(0)} kcal' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: isAdding
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt, color: Colors.orange),
            onTap: isAdding ? null : () => onTap(sc),
          ),
        );
      },
    );
  }
}

// ── Added toast ───────────────────────────────────────────────────────────────

class _ActivityAddedToast extends StatelessWidget {
  final String name;
  const _ActivityAddedToast({required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.green.shade600,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.activityAdded(name),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────

class _ConfirmActivityDialog extends StatefulWidget {
  final String title;
  final ActivityType activityType;
  final String? activityId;
  final String? activityName;
  final int initialDuration;
  final double? initialCalories;
  final double? distanceKm;

  /// MET value used to estimate calories when the user changes the
  /// duration and we have a known body weight. Falls back to
  /// [ActivityType.metValue] when no [ActivityItem] is in play.
  final double metForEstimate;
  final double? userWeightKg;
  final DateTime date;

  const _ConfirmActivityDialog({
    required this.title,
    required this.activityType,
    required this.activityId,
    required this.activityName,
    required this.initialDuration,
    this.initialCalories,
    this.distanceKm,
    required this.metForEstimate,
    required this.userWeightKg,
    required this.date,
  });

  @override
  State<_ConfirmActivityDialog> createState() =>
      _ConfirmActivityDialogState();
}

class _ConfirmActivityDialogState extends State<_ConfirmActivityDialog> {
  late TextEditingController _durationCtrl;
  late TimeOfDay _startTime;
  double? _overrideCalories;

  @override
  void initState() {
    super.initState();
    _durationCtrl =
        TextEditingController(text: widget.initialDuration.toString());
    _startTime = TimeOfDay.now();
    _overrideCalories = widget.initialCalories;
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    super.dispose();
  }

  int get _duration {
    final raw = int.tryParse(_durationCtrl.text.trim());
    return raw == null || raw <= 0 ? widget.initialDuration : raw;
  }

  /// Display kcal for the current duration. Prefers the user-typed
  /// override, then the original stored kcal scaled by the duration
  /// delta, then a MET-based estimate when weight is known.
  double? _estimatedKcal() {
    if (_overrideCalories != null &&
        _duration == widget.initialDuration) {
      return _overrideCalories;
    }
    if (widget.initialCalories != null && widget.initialDuration > 0) {
      // Scale the original by the duration ratio — cheap and reasonably
      // accurate for the same activity at a different length.
      return widget.initialCalories! * _duration / widget.initialDuration;
    }
    final w = widget.userWeightKg;
    if (w == null) return null;
    return widget.metForEstimate * w * (_duration / 60.0);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final kcal = _estimatedKcal();
    return AlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  decoration: InputDecoration(
                    labelText: l.durationMinutes,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(_startTime.format(context),
                    style: const TextStyle(fontSize: 13)),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _startTime,
                  );
                  if (picked != null) {
                    setState(() => _startTime = picked);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(widget.activityType.icon,
                    color: widget.activityType.color, size: 18),
                const SizedBox(width: 8),
                Text(
                  kcal != null
                      ? '${kcal.toStringAsFixed(0)} kcal'
                      : l.noKcalEstimate,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            final start = DateTime(
              widget.date.year,
              widget.date.month,
              widget.date.day,
              _startTime.hour,
              _startTime.minute,
            );
            final entry = PhysicalActivity(
              activityType: widget.activityType,
              activityId: widget.activityId,
              activityName: widget.activityName,
              startTime: start,
              endTime: start.add(Duration(minutes: _duration)),
              durationMinutes: _duration,
              caloriesBurned: kcal,
              distanceKm: widget.distanceKm,
              source: DataSource.manual,
            );
            Navigator.of(context)
                .pop((entry: entry, displayName: widget.title));
          },
          child: Text(l.add),
        ),
      ],
    );
  }
}
