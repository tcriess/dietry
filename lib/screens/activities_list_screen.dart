import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/gear.dart';
import '../models/physical_activity.dart';
import '../models/food_entry.dart' show MealType;
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../widgets/move_copy_sheet.dart';
import 'edit_activity_screen.dart';

/// Maps an activity's start time to the meal bucket it falls in, so the
/// move/copy sheet can pre-select a sensible meal.
MealType _mealForTime(DateTime dt) {
  final h = dt.hour;
  if (h < 11) return MealType.breakfast;
  if (h < 15) return MealType.lunch;
  if (h < 18) return MealType.snack;
  return MealType.dinner;
}

/// Representative time-of-day used when an activity is placed into a meal slot
/// other than its original one (activities store a timestamp, not a meal).
({int hour, int minute}) _timeForMeal(MealType meal) {
  switch (meal) {
    case MealType.breakfast:
      return (hour: 8, minute: 0);
    case MealType.lunch:
      return (hour: 12, minute: 30);
    case MealType.snack:
      return (hour: 15, minute: 30);
    case MealType.dinner:
      return (hour: 19, minute: 0);
  }
}

/// Screen zur Anzeige aller Aktivitäten eines Tages
class ActivitiesListScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;
  final bool canGoBack;
  final bool canGoForward;
  final Future<void> Function()? onRefresh;

  const ActivitiesListScreen({
    super.key,
    required this.dbService,
    required this.selectedDay,
    required this.onChangeDay,
    required this.onJumpToToday,
    required this.canGoBack,
    required this.canGoForward,
    this.onRefresh,
  });

  @override
  State<ActivitiesListScreen> createState() => _ActivitiesListScreenState();
}

class _ActivitiesListScreenState extends State<ActivitiesListScreen> {
  final _store = DataStore.instance;

  /// All of the user's gear, retired included. Retired items are filtered out
  /// of the picker but must stay here: an old activity attributed to a retired
  /// pair of shoes still has to show their name rather than fall back to the
  /// "which gear?" prompt.
  List<Gear> _gear = [];

  /// Gear ids we already went back to the store for and still could not
  /// resolve. Stops a genuinely dangling reference from re-triggering a reload
  /// on every single store change.
  final Set<String> _unresolvableGearIds = {};

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _loadGear();
  }

  /// In-flight load, shared rather than duplicated so a caller that awaits this
  /// (the picker) really does get fresh data instead of silently skipping.
  Future<void>? _gearLoad;

  Future<void> _loadGear() =>
      _gearLoad ??= _fetchGear().whenComplete(() => _gearLoad = null);

  Future<void> _fetchGear() async {
    final gear = await SyncService.instance.getGear();
    if (!mounted) return;
    setState(() {
      _gear = gear;
      _unresolvableGearIds
          .removeWhere((id) => gear.any((g) => g.id == id));
    });
  }

  /// Gear ids referenced by today's activities that [_gear] doesn't contain —
  /// i.e. gear created after this screen loaded its list.
  Set<String> _unresolvedGearIds() => {
        for (final a in _store.activities)
          if (a.gearId != null && !_gear.any((g) => g.id == a.gearId))
            a.gearId!,
      };

  /// Assign (or clear) the gear on an activity, straight from the list.
  ///
  /// This exists because the alternating-shoes case makes correcting an import
  /// a routine act, not an exception: with two pairs both set to auto-attach to
  /// running, no default can be right more than half the time. Doing it through
  /// the edit screen — open, scroll, change dropdown, save — is far too much
  /// friction for something you do after every run.
  Future<void> _pickGear(PhysicalActivity activity) async {
    final l = AppLocalizations.of(context)!;

    // Refresh first: gear created since this screen mounted would otherwise be
    // missing from the sheet, which is exactly when the user reaches for it —
    // they just added the bike they now want to attach.
    await _loadGear();
    if (!mounted) return;

    // Retired gear is hidden, except the item already on this activity, which
    // has to stay visible so it shows as the current selection.
    final options = _gear
        .where((g) => !g.retired || g.id == activity.gearId)
        .toList();

    final chosen = await showModalBottomSheet<({Gear? gear})>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l.gearTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.not_interested),
              title: Text(l.gearNone),
              selected: activity.gearId == null,
              onTap: () => Navigator.of(ctx).pop((gear: null)),
            ),
            for (final g in options)
              ListTile(
                leading: Icon(g.category.icon),
                title: Text(g.name),
                selected: g.id == activity.gearId,
                trailing: g.id == activity.gearId
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.of(ctx).pop((gear: g)),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    // copyWith cannot set a field back to null, hence the explicit clear flag.
    final updated = chosen.gear == null
        ? activity.copyWith(clearGearId: true)
        : activity.copyWith(gearId: chosen.gear!.id);

    _store.replaceActivity(updated); // optimistic — the row updates immediately
    final saved = await SyncService.instance.updateActivity(updated);
    if (saved != null) _store.replaceActivity(saved);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // On a cold start this screen can mount and call _loadGear() before
    // SyncService has its db/local/cache wired, so getGear() returns [] and the
    // chips never appear. The store fills in shortly after (local mirror, then
    // server reconcile) and fires this callback — take that as our cue to retry
    // the gear load. Cheap: getGear() is a local query.
    //
    // The list also goes stale the other way round: gear created *after* this
    // screen mounted (from the Gear screen, then assigned in the activity
    // detail view) is missing here, so the chip cannot resolve the id and falls
    // back to "which gear?" on an activity that plainly has some. Reloading
    // when an activity points at gear we don't know fixes that.
    final unresolved = _unresolvedGearIds()
      ..removeAll(_unresolvableGearIds);
    if (_gear.isEmpty || unresolved.isNotEmpty) {
      _unresolvableGearIds.addAll(unresolved);
      _loadGear();
    }
    setState(() {});
  }

  /// The delete confirmation, shared by the swipe gesture and the long-press
  /// sheet. Returns true when the user went through with it.
  Future<bool> _confirmDeleteActivity(PhysicalActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final ld = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(ld.deleteActivityTitle),
          content: Text(ld.deleteActivityConfirm(activity.displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(ld.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(ld.delete),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _deleteActivity(PhysicalActivity activity) async {
    final l = AppLocalizations.of(context)!;
    _store.removeActivity(activity.id!);
    await SyncService.instance.deleteActivity(activity.id!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.activityDeleted), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _editActivity(PhysicalActivity activity) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditActivityScreen(
          dbService: widget.dbService,
          activity: activity,
        ),
      ),
    );
    // The detail view can attach gear this screen has never heard of, and its
    // dropdown loads the current list while we still hold an older one.
    await _loadGear();
  }

  /// Long-press handler: copy, move or delete [activity]. The chosen meal maps
  /// to a representative start time on the target day (the original time is
  /// kept when the meal is unchanged); the duration is preserved. A copy is a
  /// fresh manual entry; a move re-dates in place; a delete asks first.
  Future<void> _moveCopyActivity(PhysicalActivity activity) async {
    final currentMeal = _mealForTime(activity.startTime);
    final result = await showMoveCopySheet(
      context,
      title: activity.displayName,
      initialMeal: currentMeal,
    );
    if (result == null || !mounted) return;

    if (result.action == MoveCopyAction.delete) {
      if (await _confirmDeleteActivity(activity) && mounted) {
        await _deleteActivity(activity);
      }
      return;
    }

    final l = AppLocalizations.of(context)!;
    final sync = SyncService.instance;

    final int hour, minute;
    if (result.meal == currentMeal) {
      hour = activity.startTime.hour;
      minute = activity.startTime.minute;
    } else {
      final t = _timeForMeal(result.meal);
      hour = t.hour;
      minute = t.minute;
    }
    final newStart = DateTime(result.day.year, result.day.month, result.day.day,
        hour, minute, activity.startTime.second);
    final newEnd =
        newStart.add(activity.endTime.difference(activity.startTime));

    try {
      if (result.action == MoveCopyAction.copy) {
        // A copy is a fresh manual entry: no id and no Health Connect link, so
        // it can't collide with the source on the (user_id, hc_record_id)
        // unique constraint (which would silently no-op the insert).
        await sync.saveActivity(PhysicalActivity(
          activityType: activity.activityType,
          activityId: activity.activityId,
          activityName: activity.activityName,
          startTime: newStart,
          endTime: newEnd,
          durationMinutes: activity.durationMinutes,
          caloriesBurned: activity.caloriesBurned,
          distanceKm: activity.distanceKm,
          steps: activity.steps,
          avgHeartRate: activity.avgHeartRate,
          notes: activity.notes,
          source: DataSource.manual,
          gearId: activity.gearId,
        ));
      } else {
        await sync.updateActivity(
            activity.copyWith(startTime: newStart, endTime: newEnd));
      }
      await _store.loadDay(widget.selectedDay, silent: true);
    } catch (e) {
      appLogger.e('Move/copy activity failed: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.action == MoveCopyAction.copy
            ? l.activityCopied
            : l.activityMoved),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// The gear currently on [activity], as a tappable chip. Unassigned runs show
  /// a dashed "which shoes?" affordance rather than nothing — an imported run
  /// with no gear is the case that needs fixing, so it must be the visible one.
  /// Whether the gear chip belongs on [activity].
  ///
  /// Gear is only a thing for some activities, and the chip should not sit
  /// unanswered under every yoga session. Distance used to be the whole test,
  /// which quietly hid the chip on exactly the imports that needed it: a ride
  /// arrives without a distance whenever the source did not export one, and
  /// then there was no way to attach the bike at all. Owning gear that claims
  /// the activity type is the better signal, with distance kept as the
  /// fallback for gear that declares no default type.
  bool _showsGearChip(PhysicalActivity activity) {
    if (activity.gearId != null) return true;
    if (_gear.isEmpty) return false;
    if (_gear.any((g) =>
        !g.retired && g.defaultActivityType == activity.activityType)) {
      return true;
    }
    return activity.distanceKm != null;
  }

  Widget _buildGearChip(AppLocalizations l, PhysicalActivity activity) {
    Gear? gear;
    for (final g in _gear) {
      if (g.id == activity.gearId) {
        gear = g;
        break;
      }
    }
    final assigned = gear != null;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => _pickGear(activity),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: assigned ? Colors.blue.shade200 : Colors.orange.shade300,
            ),
            color: assigned ? Colors.blue.shade50 : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                assigned ? gear.category.icon : Icons.help_outline,
                size: 13,
                color: assigned ? Colors.blue.shade700 : Colors.orange.shade800,
              ),
              const SizedBox(width: 4),
              Text(
                assigned ? gear.name : l.gearAssignPrompt,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      assigned ? Colors.blue.shade800 : Colors.orange.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) return '${hours}h ${mins}min';
    return '${mins}min';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.selectedDay);
    final isToday = DateUtils.isSameDay(widget.selectedDay, DateTime.now());
    final activities = _store.activities;

    final totalDuration = activities.fold(0, (sum, a) => sum + (a.durationMinutes ?? a.calculatedDuration));
    final totalCalories = activities.fold(0.0, (sum, a) => sum + (a.caloriesBurned ?? 0));

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Visibility(
                  visible: widget.canGoBack,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: l.previousDay,
                    onPressed: () => widget.onChangeDay(-1),
                  ),
                ),
                Column(
                  children: [
                    Text(l.activitiesTitle, style: Theme.of(context).textTheme.headlineSmall),
                    Text(formattedDate, style: Theme.of(context).textTheme.bodyMedium),
                    if (!isToday)
                      TextButton(
                        onPressed: widget.onJumpToToday,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l.today, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                Visibility(
                  visible: widget.canGoForward,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: l.nextDay,
                    onPressed: () => widget.onChangeDay(1),
                  ),
                ),
              ],
            ),
          ),

          if (activities.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      const Icon(Icons.timer, color: Colors.blue),
                      const SizedBox(height: 4),
                      Text(_formatDuration(totalDuration),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(l.activityTotal, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    if (totalCalories > 0)
                      Column(children: [
                        const Icon(Icons.local_fire_department, color: Colors.orange),
                        const SizedBox(height: 4),
                        Text(totalCalories.toStringAsFixed(0),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('kcal', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    Column(children: [
                      const Icon(Icons.fitness_center, color: Colors.green),
                      const SizedBox(height: 4),
                      Text('${activities.length}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(l.activitiesTitle, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ],
                ),
              ),
            ),

          const Divider(height: 1),

          Expanded(
            child: _store.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _wrapWithRefresh(activities.isEmpty
                    ? LayoutBuilder(
                        builder: (ctx, c) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: c.maxHeight),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_run,
                                      size: 64,
                                      color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(l.activitiesEmpty,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              color: Colors.grey.shade600)),
                                  const SizedBox(height: 8),
                                  Text(l.activitiesEmptyHint,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(bottom: 88 + MediaQuery.paddingOf(context).bottom),
                        itemCount: activities.length,
                        itemBuilder: (context, index) {
                          final activity = activities[index];
                          final timeFormat = DateFormat.Hm();
                          return Dismissible(
                            key: Key(activity.id!),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (direction) =>
                                _confirmDeleteActivity(activity),
                            onDismissed: (direction) => _deleteActivity(activity),
                            child: Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade100,
                                  child: const Icon(Icons.fitness_center, color: Colors.blue),
                                ),
                                title: Text(activity.displayName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${timeFormat.format(activity.startTime)} • '
                                      '${_formatDuration(activity.durationMinutes ?? activity.calculatedDuration)}'
                                      '${activity.distanceKm != null ? ' • ${activity.distanceKm!.toStringAsFixed(1)} km' : ''}'
                                      '${activity.caloriesBurned != null ? ' • ${activity.caloriesBurned!.toStringAsFixed(0)} kcal' : ''}',
                                    ),
                                    // Gear, one tap away — see [_showsGearChip].
                                    if (_showsGearChip(activity))
                                      _buildGearChip(l, activity),
                                  ],
                                ),
                                // Deleting straight from the row is offered for
                                // today's log only: a mis-tap while browsing an
                                // older day would drop history that is no longer
                                // being watched. Past activities are deleted
                                // from the long-press sheet.
                                trailing: DateUtils.isSameDay(
                                        activity.startTime, DateTime.now())
                                    ? IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20),
                                        color: Colors.red.shade400,
                                        onPressed: () =>
                                            _deleteActivity(activity),
                                        tooltip: l.delete,
                                      )
                                    : null,
                                onTap: () => _editActivity(activity),
                                onLongPress: () => _moveCopyActivity(activity),
                              ),
                            ),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  /// Wrap [child] in a [RefreshIndicator] when an onRefresh callback was
  /// supplied; otherwise return the child unchanged.
  Widget _wrapWithRefresh(Widget child) {
    final refresh = widget.onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(onRefresh: refresh, child: child);
  }
}
