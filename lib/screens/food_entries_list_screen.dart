import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import 'dart:convert' show base64Decode;
import '../app_features.dart';
import '../models/food_entry.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/food_image_service.dart';
import '../services/food_entry_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import 'edit_food_entry_screen.dart';

/// Screen zur Anzeige und Verwaltung aller Food-Entries eines Tages
class FoodEntriesListScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;
  final bool canGoBack;
  final bool canGoForward;
  final Future<void> Function()? onRefresh;

  const FoodEntriesListScreen({
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
  State<FoodEntriesListScreen> createState() => _FoodEntriesListScreenState();
}

class _FoodEntriesListScreenState extends State<FoodEntriesListScreen> {
  final _store = DataStore.instance;
  final _imageCache = <String, String?>{};
  late FoodImageService _imageService;

  /// Cached entries from the day before [widget.selectedDay], used to power
  /// the "Repeat yesterday's …" chip on empty meal groups. Loaded lazily on
  /// init and refreshed whenever [widget.selectedDay] changes. Null while a
  /// fetch is in flight; empty list when the previous day had no entries.
  List<FoodEntry>? _previousDayEntries;
  bool _repeatingMeal = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    if (widget.dbService != null) {
      _imageService = FoodImageService(widget.dbService!);
      _loadImagesForEntries(_store.foodEntries);
      _loadPreviousDayEntries();
    }
  }

  @override
  void didUpdateWidget(covariant FoodEntriesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _previousDayEntries = null;
      _loadPreviousDayEntries();
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> _loadPreviousDayEntries() async {
    final db = widget.dbService;
    if (db == null) return;
    final previousDay =
        widget.selectedDay.subtract(const Duration(days: 1));
    try {
      final entries =
          await FoodEntryService(db).getFoodEntriesForDate(previousDay);
      if (!mounted) return;
      if (!DateUtils.isSameDay(
          previousDay, widget.selectedDay.subtract(const Duration(days: 1)))) {
        // selectedDay changed while we were fetching — discard stale result.
        return;
      }
      setState(() => _previousDayEntries = entries);
    } catch (e) {
      appLogger.d('Repeat-meal: previous-day fetch failed: $e');
    }
  }

  /// Bulk-copies [sourceEntries] into [widget.selectedDay]. Each entry is
  /// re-created with a fresh id and today's date; everything else (name,
  /// macros, foodId, amount, unit, mealType) is preserved.
  Future<void> _repeatMeal(
      MealType mealType, List<FoodEntry> sourceEntries) async {
    if (_repeatingMeal || sourceEntries.isEmpty) return;
    setState(() => _repeatingMeal = true);
    final sync = SyncService.instance;
    final now = DateTime.now();
    try {
      for (final src in sourceEntries) {
        final copy = src.copyWith(
          id: '',
          entryDate: widget.selectedDay,
          createdAt: now,
          updatedAt: now,
        );
        await sync.createFoodEntry(copy);
      }
      await _store.loadDay(widget.selectedDay, silent: true, delta: true);
    } catch (e) {
      appLogger.e('Repeat-meal failed: $e');
    } finally {
      if (mounted) setState(() => _repeatingMeal = false);
    }
  }

  /// Renders one or more "Repeat …" chips for an empty meal group. Always
  /// includes yesterday's same meal-type when available; for lunch also
  /// surfaces yesterday's dinner (leftovers-as-tomorrow's-lunch pattern),
  /// for dinner also surfaces today's lunch (same-day-leftover pattern).
  /// Returns [SizedBox.shrink] when no suggestions apply.
  Widget _buildRepeatChipForEmptyMeal(
      AppLocalizations l, MealType mealType, List<FoodEntry> todayEntries) {
    final prev = _previousDayEntries;
    final suggestions = <({String label, List<FoodEntry> sources})>[];

    if (prev != null) {
      final sameYesterday =
          prev.where((e) => e.mealType == mealType).toList();
      if (sameYesterday.isNotEmpty) {
        suggestions.add((
          label: l.repeatYesterdaysMeal(mealType.localizedName(l)),
          sources: sameYesterday,
        ));
      }
      if (mealType == MealType.lunch) {
        final ydDinner =
            prev.where((e) => e.mealType == MealType.dinner).toList();
        if (ydDinner.isNotEmpty) {
          suggestions.add((
            label: l.repeatYesterdaysMeal(
                MealType.dinner.localizedName(l)),
            sources: ydDinner,
          ));
        }
      }
    }

    if (mealType == MealType.dinner) {
      final todayLunch =
          todayEntries.where((e) => e.mealType == MealType.lunch).toList();
      if (todayLunch.isNotEmpty) {
        suggestions.add((
          label: l.repeatTodaysMeal(MealType.lunch.localizedName(l)),
          sources: todayLunch,
        ));
      }
    }

    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(mealType.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                mealType.localizedName(l),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in suggestions)
                ActionChip(
                  avatar: _repeatingMeal
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.replay, size: 18),
                  label: Text('${s.label} (${s.sources.length})'),
                  onPressed: _repeatingMeal
                      ? null
                      : () => _repeatMeal(mealType, s.sources),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _onStoreChanged() {
    _loadImagesForEntries(_store.foodEntries);
    if (mounted) setState(() {});
  }

  void _loadImagesForEntries(List<FoodEntry> entries) {
    if (widget.dbService == null) return;
    final jwt = widget.dbService!.jwt;
    final apiUrl = NeonDatabaseService.dataApiUrl;

    for (final entry in entries) {
      // Priority: meal template image > food image
      final mealTemplateId = entry.mealTemplateId;
      final foodId = entry.foodId;

      if (mealTemplateId != null) {
        final cacheKey = 'meal_$mealTemplateId';
        if (_imageCache.containsKey(cacheKey)) continue;
        _imageCache[cacheKey] = null; // mark as in-progress
        _loadMealImage(mealTemplateId, cacheKey, jwt, apiUrl);
      } else if (foodId != null) {
        if (_imageCache.containsKey(foodId)) continue;
        _imageCache[foodId] = null; // mark as in-progress
        _imageService.fetchImage(foodId).then((imageData) {
          if (mounted && imageData != null) {
            setState(() { _imageCache[foodId] = imageData; });
          }
        });
      }
    }
  }

  Future<void> _loadMealImage(String mealTemplateId, String cacheKey, String? jwt, String apiUrl) async {
    if (jwt == null || widget.dbService == null) return;
    try {
      // Use cloud edition's MealImageService via PostgREST
      final response = await widget.dbService!.dioClient.get(
        '/meal_images?template_id=eq.$mealTemplateId',
      );

      if (response.data is List && (response.data as List).isNotEmpty) {
        final imageData = response.data[0]['image_data'] as String?;
        if (mounted && imageData != null) {
          setState(() { _imageCache[cacheKey] = imageData; });
        }
      }
    } catch (e) {
      appLogger.d('Failed to load meal image for $mealTemplateId: $e');
    }
  }

  Widget _buildEntryLeading(FoodEntry entry, MealType mealType) {
    // Priority: meal template image > food image > emoji
    final mealTemplateId = entry.mealTemplateId;
    if (mealTemplateId != null) {
      final cacheKey = 'meal_$mealTemplateId';
      final cached = _imageCache[cacheKey];
      if (cached != null) {
        try {
          return CircleAvatar(backgroundImage: MemoryImage(base64Decode(cached)));
        } catch (_) {}
      }
    }

    final foodId = entry.foodId;
    if (foodId != null) {
      final cached = _imageCache[foodId];
      if (cached != null) {
        try {
          return CircleAvatar(backgroundImage: MemoryImage(base64Decode(cached)));
        } catch (_) {}
      }
    }

    return CircleAvatar(
      backgroundColor: _getMealTypeColor(mealType),
      child: Text(mealType.icon, style: const TextStyle(fontSize: 20)),
    );
  }

  Future<void> _deleteEntry(FoodEntry entry) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final ld = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(ld.deleteEntryTitle),
          content: Text(ld.deleteEntryConfirm(entry.name)),
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

    if (confirmed != true) return;

    // Optimistic remove — UI updates immediately.
    _store.removeFoodEntry(entry.id);

    await SyncService.instance.deleteFoodEntry(entry.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.entryDeleted),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _editEntry(FoodEntry entry) async {
    // EditFoodEntryScreen updates DataStore directly on save.
    // dbService can be null in guest mode (will use LocalDataService via SyncService)
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditFoodEntryScreen(
          dbService: widget.dbService,
          entry: entry,
        ),
      ),
    );
  }
  
  /// Formatiert Menge + Einheit für die Anzeige.
  /// g/ml: "150g", "250ml" — benannte Portion: "1 Scheibe (30g)"
  String _formatEntryAmount(FoodEntry entry) {
    final unit = entry.unit;
    if (unit == 'g' || unit == 'ml') {
      return '${entry.amount.toStringAsFixed(0)}$unit';
    }
    // Meal template entries: amount is portion count.
    if (unit == 'Portion') {
      final count = entry.amount;
      final countStr = count == count.truncateToDouble()
          ? count.toInt().toString()
          : count.toStringAsFixed(1);
      return count == 1.0 ? '1 Portion' : '$countStr Portionen';
    }
    // Named food portion: amount is portion count.
    final count = entry.amount;
    final countStr = count == count.truncateToDouble()
        ? count.toInt().toString()
        : count.toStringAsFixed(1);
    return '$countStr × $unit';
  }

  /// Farbe für Meal-Type Avatar
  Color _getMealTypeColor(MealType mealType) {
    switch (mealType) {
      case MealType.breakfast:
        return Colors.orange.shade100;
      case MealType.lunch:
        return Colors.blue.shade100;
      case MealType.dinner:
        return Colors.purple.shade100;
      case MealType.snack:
        return Colors.green.shade100;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    // In guest mode, dbService is null; show basic view without images/search
    if (widget.dbService == null) {
      final formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.selectedDay);
      final isToday = DateUtils.isSameDay(widget.selectedDay, DateTime.now());
      final entries = _store.foodEntries;

      final guestScroll = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
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
                        Text(
                          l.entriesTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          formattedDate,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No entries for this day'),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(entry.name),
                      subtitle: Text('${entry.amount} ${entry.unit}'),
                      trailing: Text('${entry.calories.toStringAsFixed(0)} kcal'),
                    );
                  },
                ),
            ],
          ),
      );

      final refresh = widget.onRefresh;
      return Scaffold(
        body: refresh == null
            ? guestScroll
            : RefreshIndicator(onRefresh: refresh, child: guestScroll),
      );
    }

    final formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.selectedDay);
    final isToday = DateUtils.isSameDay(widget.selectedDay, DateTime.now());
    final entries = _store.foodEntries;

    return Scaffold(
      body: Column(
        children: [
          // Tagesauswahl
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
                    Text(
                      l.entriesTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      formattedDate,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: widget.onJumpToToday,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l.today,
                            style: const TextStyle(fontSize: 12)),
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

          const Divider(height: 1),

          // Entry-Liste
          Expanded(
            child: _store.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _wrapWithRefresh(entries.isEmpty
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
                                  Icon(Icons.no_food,
                                      size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    l.entriesEmpty,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.grey.shade600,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l.entriesEmptyHint,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.grey.shade500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.only(bottom: 88 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          // Gruppiere nach Meal-Type
                          ...MealType.values.map((mealType) {
                            final mealEntries = entries.where((e) => e.mealType == mealType).toList();
                            if (mealEntries.isEmpty) {
                              return _buildRepeatChipForEmptyMeal(
                                  l, mealType, entries);
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Meal-Type Header
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  child: Row(
                                    children: [
                                      Text(mealType.icon, style: const TextStyle(fontSize: 24)),
                                      const SizedBox(width: 8),
                                      Text(
                                        mealType.localizedName(l),
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      // Summe für diese Mahlzeit (only show if not macro-only mode)
                                      if (_store.goal?.macroOnly != true)
                                        Text(
                                          '${mealEntries.fold(0.0, (sum, e) => sum + e.calories).toStringAsFixed(0)} kcal',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // Entries für diese Mahlzeit
                                ...mealEntries.map((entry) => Dismissible(
                                  key: Key(entry.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    color: Colors.red,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (context) {
                                        final ld = AppLocalizations.of(context)!;
                                        return AlertDialog(
                                          title: Text(ld.deleteEntryTitle),
                                          content: Text(ld.deleteEntryConfirm(entry.name)),
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
                                  },
                                  onDismissed: (direction) {
                                    _deleteEntry(entry);
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: ListTile(
                                      leading: _buildEntryLeading(entry, mealType),
                                      title: Text(entry.name),
                                      subtitle: Text(
                                        _store.goal?.macroOnly == true
                                            ? _formatEntryAmount(entry)
                                            : '${_formatEntryAmount(entry)} • ${entry.calories.toStringAsFixed(0)} kcal',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Makros
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'P: ${entry.protein.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                              Text(
                                                'F: ${entry.fat.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                              Text(
                                                'C: ${entry.carbs.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 4),
                                          // Mikronährstoffe (Premium)
                                          if (AppFeatures.microNutrients)
                                            IconButton(
                                              icon: const Icon(Icons.science_outlined, size: 20),
                                              onPressed: () {
                                                final db = widget.dbService;
                                                if (db == null) return;
                                                final jwt = db.jwt;
                                                final userId = db.userId;
                                                if (jwt == null || userId == null) return;
                                                premiumFeatures.showMicroNutrientsSheet(
                                                  context: context,
                                                  entryId: entry.id,
                                                  entryName: entry.name,
                                                  userId: userId,
                                                  authToken: jwt,
                                                  apiUrl: NeonDatabaseService.dataApiUrl,
                                                );
                                              },
                                              tooltip: 'Mikronährstoffe',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32,
                                              ),
                                            ),
                                          // Löschen-Button
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 20),
                                            color: Colors.red.shade400,
                                            onPressed: () => _deleteEntry(entry),
                                            tooltip: l.delete,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _editEntry(entry),
                                    ),
                                  ),
                                )),
                                
                                const SizedBox(height: 8),
                              ],
                            );
                          }),
                        ],
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

