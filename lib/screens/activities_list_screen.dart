import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
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
  }

  /// Long-press handler: copy or move [activity] to another day / meal. The
  /// chosen meal maps to a representative start time on the target day (the
  /// original time is kept when the meal is unchanged); the duration is
  /// preserved. A copy is a fresh manual entry; a move re-dates in place.
  Future<void> _moveCopyActivity(PhysicalActivity activity) async {
    final currentMeal = _mealForTime(activity.startTime);
    final result = await showMoveCopySheet(
      context,
      title: activity.displayName,
      initialDay: activity.startTime,
      initialMeal: currentMeal,
    );
    if (result == null || !mounted) return;

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
                      Text('Gesamt', style: Theme.of(context).textTheme.bodySmall),
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
                            confirmDismiss: (direction) async {
                              return await showDialog<bool>(
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
                            },
                            onDismissed: (direction) => _deleteActivity(activity),
                            child: Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade100,
                                  child: const Icon(Icons.fitness_center, color: Colors.blue),
                                ),
                                title: Text(activity.displayName),
                                subtitle: Text(
                                  '${timeFormat.format(activity.startTime)} • '
                                  '${_formatDuration(activity.durationMinutes ?? activity.calculatedDuration)}'
                                  '${activity.distanceKm != null ? ' • ${activity.distanceKm!.toStringAsFixed(1)} km' : ''}'
                                  '${activity.caloriesBurned != null ? ' • ${activity.caloriesBurned!.toStringAsFixed(0)} kcal' : ''}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  color: Colors.red.shade400,
                                  onPressed: () => _deleteActivity(activity),
                                  tooltip: l.delete,
                                ),
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
