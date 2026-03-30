import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../app_features.dart';
import '../models/physical_activity.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/physical_activity_service.dart';
import '../services/health_connect_service.dart';
import '../l10n/app_localizations.dart';
import 'add_activity_screen.dart';
import 'activity_database_screen.dart';
import 'edit_activity_screen.dart';

/// Screen zur Anzeige aller Aktivitäten eines Tages
class ActivitiesListScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;

  const ActivitiesListScreen({
    super.key,
    required this.dbService,
    required this.selectedDay,
    required this.onChangeDay,
    required this.onJumpToToday,
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
    // Optimistic remove.
    _store.removeActivity(activity.id!);

    await SyncService.instance.deleteActivity(activity.id!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.activityDeleted),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  Future<void> _showActivityQuickAdd() async {
    final db = widget.dbService;
    final jwt = db.jwt;
    final userId = db.userId;
    if (jwt == null || userId == null) return;

    premiumFeatures.showActivityQuickAddSheet(
      context: context,
      userId: userId,
      authToken: jwt,
      apiUrl: NeonDatabaseService.dataApiUrl,
      date: widget.selectedDay,
      onAdd: (data) async {
        final activity = PhysicalActivity(
          activityType: ActivityType.values.firstWhere(
            (t) => t.name == data.activityType,
            orElse: () => ActivityType.other,
          ),
          activityId: data.activityId,
          activityName: data.activityName,
          startTime: data.startTime,
          endTime: data.endTime,
          durationMinutes: data.durationMinutes,
          caloriesBurned: data.caloriesBurned,
          distanceKm: data.distanceKm,
          source: DataSource.manual,
        );
        final saved = await SyncService.instance.saveActivity(activity);
        _store.addActivity(saved ?? activity);
      },
    );
  }

  Future<void> _importFromHealthConnect() async {
    final l = AppLocalizations.of(context)!;
    if (!HealthConnectService.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.healthConnectUnavailable)),
      );
      return;
    }

    final hc = HealthConnectService();
    final granted = await hc.requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.healthConnectUnavailable)),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.healthConnectImporting)),
    );

    try {
      // Import only the selected day (local timezone: midnight–23:59:59).
      final d = widget.selectedDay;
      final start = DateTime(d.year, d.month, d.day);
      final end = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
      final imported = await hc.importActivities(start: start, end: end);

      if (imported.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.healthConnectNoResults)),
          );
        }
        return;
      }

      final service = PhysicalActivityService(widget.dbService);
      // Lade vorhandene HC-IDs um Duplikate zu vermeiden
      final existing = await service.getActivitiesInRange(start: start, end: end);
      final existingHcIds = existing
          .map((a) => a.healthConnectRecordId)
          .whereType<String>()
          .toSet();

      final toSave = imported
          .where((a) => a.healthConnectRecordId == null ||
              !existingHcIds.contains(a.healthConnectRecordId))
          .toList();

      for (final activity in toSave) {
        final saved = await SyncService.instance.saveActivity(activity);
        // Add to store with the server-returned entity (has real id) if available.
        _store.addActivity(saved ?? activity);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.healthConnectSuccess(toSave.length)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.healthConnectError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    // DataStore is updated directly by EditActivityScreen.
  }
  
  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${mins}min';
    } else {
      return '${mins}min';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.selectedDay);
    final isToday = DateUtils.isSameDay(widget.selectedDay, DateTime.now());
    final activities = _store.activities;

    // Berechne Gesamt-Statistiken
    final totalDuration = activities.fold(0, (sum, a) => sum + (a.durationMinutes ?? a.calculatedDuration));
    final totalCalories = activities.fold(0.0, (sum, a) => sum + (a.caloriesBurned ?? 0));

    return Scaffold(
      body: Column(
        children: [
          // Tagesauswahl
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: l.previousDay,
                  onPressed: () => widget.onChangeDay(-1),
                ),
                Column(
                  children: [
                    Text(
                      l.activitiesTitle,
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
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: l.nextDay,
                  onPressed: () => widget.onChangeDay(1),
                ),
              ],
            ),
          ),
          
          // Tages-Statistik
          if (activities.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.timer, color: Colors.blue),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(totalDuration),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gesamt',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (totalCalories > 0)
                      Column(
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.orange),
                          const SizedBox(height: 4),
                          Text(
                            totalCalories.toStringAsFixed(0),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'kcal',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    Column(
                      children: [
                        const Icon(Icons.fitness_center, color: Colors.green),
                        const SizedBox(height: 4),
                        Text(
                          '${activities.length}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          l.activitiesTitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          const Divider(height: 1),
          
          // Aktivitäten-Liste
          Expanded(
            child: _store.isLoading
                ? const Center(child: CircularProgressIndicator())
                : activities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_run, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              l.activitiesEmpty,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.activitiesEmptyHint,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
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
                            onDismissed: (direction) {
                              _deleteActivity(activity);
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade100,
                                  child: const Icon(
                                    Icons.fitness_center,
                                    color: Colors.blue,
                                  ),
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
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (AppFeatures.activityQuickAdd) ...[
            FloatingActionButton(
              heroTag: 'fab_activity_quick_add',
              onPressed: _showActivityQuickAdd,
              tooltip: 'Schnelleintrag',
              child: const Icon(Icons.bolt),
            ),
            const SizedBox(width: 12),
          ],
          if (HealthConnectService.isSupported)
            FloatingActionButton(
              heroTag: 'fab_health_connect',
              onPressed: _importFromHealthConnect,
              tooltip: l.importHealthConnect,
              child: const Icon(Icons.health_and_safety_outlined),
            ),
          if (HealthConnectService.isSupported) const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'fab_activity_database',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ActivityDatabaseScreen(dbService: widget.dbService),
                ),
              );
            },
            tooltip: l.myActivities,
            child: const Icon(Icons.storage_outlined),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'fab_add_activity',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AddActivityScreen(
                    dbService: widget.dbService,
                    selectedDate: widget.selectedDay,
                  ),
                ),
              );
              // DataStore is updated directly by AddActivityScreen.
            },
            icon: const Icon(Icons.add),
            label: Text(l.addActivity),
          ),
        ],
      ),
    );
  }
}

