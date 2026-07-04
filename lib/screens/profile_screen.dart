import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../services/user_profile_service.dart';
import '../services/user_body_measurements_service.dart';
import '../services/nutrition_goal_service.dart';
import '../services/nutrition_calculator.dart';
import '../services/local_data_service.dart';
import '../services/data_store.dart';
import '../services/neon_database_service.dart';
import '../services/neon_auth_service.dart';
import '../services/health_connect_service.dart';
import '../services/health_connect_prefs.dart';
import '../services/account_service.dart';
import '../services/water_reminder_service.dart';
import '../services/food_log_reminder_service.dart';
import '../services/app_logger.dart';
import '../app_config.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_features_utils.dart';
import '../widgets/main_tutorial.dart';
import 'profile_setup_screen.dart';
import 'add_body_measurement_screen.dart';
import 'goal_recommendation_screen.dart';

enum _MeasurementRange { month1, months3, months6, year1, all }

/// Profil-Screen mit getrennten statischen/zeitbasierten Daten
class ProfileScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final NeonAuthService authService;
  final bool isGuestMode;

  const ProfileScreen({
    super.key,
    required this.dbService,
    required this.authService,
    this.isGuestMode = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  UserBodyMeasurement? _currentMeasurement;
  List<UserBodyMeasurement> _allMeasurements = [];
  NutritionGoal? _goal;
  bool _isLoading = true;
  _MeasurementRange _selectedRange = _MeasurementRange.months3;
  bool _waterReminderEnabled = false;
  bool _foodLogReminderEnabled = false;
  bool _hcImportEnabled = false;

  @override
  void initState() {
    super.initState();
    // Guest mode: show empty state
    if (widget.isGuestMode) {
      _isLoading = false;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final db = widget.dbService;

    // Local-first: paint cached profile/measurements/goal instantly (clears the
    // full-screen spinner if the cache has anything), then reconcile from the
    // server and write the fresh data back to the cache.
    await _hydrateFromCache();

    try {
      final profileService = UserProfileService(db);
      final measurementService = UserBodyMeasurementsService(db);
      final goalService = NutritionGoalService(db);

      final end = DateTime.now();
      final start = _rangeStart(end);

      final measurementsFuture = start != null
          ? measurementService.getMeasurementsInRange(start: start, end: end)
          : measurementService.getAllMeasurements();

      final results = await Future.wait([
        profileService.getCurrentProfile(),
        measurementService.getCurrentMeasurement(),
        measurementsFuture,
        goalService.getGoalForDate(DateTime.now()),
      ]);
      final reminderEnabled = await WaterReminderService.isEnabled();
      final foodLogReminderEnabled = await FoodLogReminderService.isEnabled();
      final hcEnabled = await HealthConnectPrefs.isEnabled();

      final profile = results[0] as UserProfile?;
      final current = results[1] as UserBodyMeasurement?;
      final measurements = results[2] as List<UserBodyMeasurement>;
      final goal = results[3] as NutritionGoal?;

      if (mounted) {
        setState(() {
          _profile = profile;
          _currentMeasurement = current;
          _allMeasurements = measurements;
          _goal = goal;
          _waterReminderEnabled = reminderEnabled;
          _foodLogReminderEnabled = foodLogReminderEnabled;
          _hcImportEnabled = hcEnabled;
          _isLoading = false;
        });
      }

      // Write the fresh server data back into the cache for the next open.
      await _cacheProfileData(
        profile: profile,
        current: current,
        measurements: measurements,
        goal: goal,
      );
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Local-first hydrate: read cached profile, current measurement, measurement
  /// range and goal from the offline mirror so the screen paints without
  /// waiting on the server. Clears the spinner when the cache has any data; a
  /// cache miss leaves it up until the server responds.
  Future<void> _hydrateFromCache() async {
    if (widget.isGuestMode) return;
    try {
      final cache = LocalDataService.instance;
      final end = DateTime.now();
      final start = _rangeStart(end);

      final profile = await cache.getUserProfile();
      final current = await cache.getCurrentMeasurement();
      final measurements = start != null
          ? await cache.getMeasurementsInRange(start: start, end: end)
          : await cache.getAllMeasurements();
      final goal = await cache.getGoalForDate(DateTime.now());

      final hasData = profile != null ||
          current != null ||
          measurements.isNotEmpty ||
          goal != null;
      if (hasData && mounted) {
        setState(() {
          _profile = profile;
          _currentMeasurement = current;
          _allMeasurements = measurements;
          _goal = goal;
          _isLoading = false; // paint cached data, hide the spinner
        });
      }
    } catch (e) {
      appLogger.w('⚠️ Profile cache hydrate failed: $e');
    }
  }

  /// Write-through: persist freshly-fetched profile data into the local cache.
  Future<void> _cacheProfileData({
    UserProfile? profile,
    UserBodyMeasurement? current,
    required List<UserBodyMeasurement> measurements,
    NutritionGoal? goal,
  }) async {
    if (widget.isGuestMode) return;
    try {
      final cache = LocalDataService.instance;
      if (profile != null) await cache.saveUserProfile(profile);
      await cache.cacheMeasurements(measurements);
      if (current != null) await cache.saveMeasurement(current);
      if (goal != null) await cache.upsertGoal(goal);
    } catch (e) {
      appLogger.w('⚠️ Profile cache write-through failed: $e');
    }
  }

  /// User-triggered refresh entry point: reload screen data, then (if the
  /// HC toggle is on) pull fresh body measurements silently, re-loading the
  /// screen once more only if HC saved any new rows. Used by both the
  /// AppBar refresh icon and pull-to-refresh.
  Future<void> _userRefresh() async {
    await _loadData();
    if (!mounted || !_hcImportEnabled || !HealthConnectService.isSupported) {
      return;
    }
    final added = await _silentHcImportBodyMeasurements();
    if (added > 0 && mounted) {
      await _loadData();
    }
  }

  /// Silent HC body-measurements import for the Profile screen. Mirrors the
  /// helper in main.dart: incremental window based on [HealthConnectPrefs.lastSyncAt]
  /// with a one-day overlap; no toasts. Returns the number of saved rows.
  /// Uses [HealthConnectService.hasPermissions] (non-prompting) — silent paths
  /// must never pop a permission dialog.
  Future<int> _silentHcImportBodyMeasurements() async {
    if (!HealthConnectService.isSupported) return 0;
    final hc = HealthConnectService();
    final granted = await hc.hasPermissions();
    if (!granted) return 0;
    try {
      final end = DateTime.now();
      final lastSync = await HealthConnectPrefs.lastSyncAt();
      DateTime start;
      if (lastSync != null) {
        start = lastSync.subtract(const Duration(days: 1));
      } else {
        final earliestGoalDate =
            await NutritionGoalService(widget.dbService).getEarliestGoalDate();
        start = earliestGoalDate ?? DateTime(2000);
      }
      final imported =
          await hc.importBodyMeasurements(start: start, end: end);
      await HealthConnectPrefs.setLastSyncAt(end);
      if (imported.isEmpty) return 0;
      final service = UserBodyMeasurementsService(widget.dbService);
      for (final m in imported) {
        await service.saveMeasurement(m);
      }
      await NutritionGoalService.autoAdjustGoal(widget.dbService);
      return imported.length;
    } catch (e) {
      appLogger.w('⚠️ Silent HC body import failed: $e');
      return 0;
    }
  }

  /// Toggle the device-local "import from Health Connect" preference. On
  /// turning ON, request permissions immediately and kick off an initial
  /// body-measurements import so the chart updates without a second tap.
  /// If permissions are denied, revert the toggle and surface a snackbar.
  Future<void> _toggleHcImport(bool value) async {
    setState(() => _hcImportEnabled = value);
    await HealthConnectPrefs.setEnabled(value);
    if (!value) return;
    if (!HealthConnectService.isSupported) return;
    final hc = HealthConnectService();
    final granted = await hc.requestPermissions();
    if (!granted) {
      await HealthConnectPrefs.setEnabled(false);
      if (!mounted) return;
      setState(() => _hcImportEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.healthConnectUnavailable)),
      );
      return;
    }
    // Fire-and-forget initial body-measurement pull so the chart populates.
    // ignore: discarded_futures
    _importBodyFromHealthConnect();
  }

  DateTime? _rangeStart(DateTime end) {
    switch (_selectedRange) {
      case _MeasurementRange.month1:  return end.subtract(const Duration(days: 30));
      case _MeasurementRange.months3: return end.subtract(const Duration(days: 90));
      case _MeasurementRange.months6: return end.subtract(const Duration(days: 180));
      case _MeasurementRange.year1:   return end.subtract(const Duration(days: 365));
      case _MeasurementRange.all:     return null;
    }
  }

  Future<void> _changeRange(_MeasurementRange range) async {
    final db = widget.dbService;

    setState(() => _selectedRange = range);
    final service = UserBodyMeasurementsService(db);
    final end = DateTime.now();
    final start = _rangeStart(end);
    final measurements = start != null
        ? await service.getMeasurementsInRange(start: start, end: end)
        : await service.getAllMeasurements();
    if (mounted) setState(() => _allMeasurements = measurements);
  }

  Future<void> _editProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileSetupScreen(
          dbService: widget.dbService,
          existingProfile: _profile,
        ),
      ),
    );
    
    if (result == true) {
      _loadData();
    }
  }
  
  Future<void> _addOrEditMeasurement() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddBodyMeasurementScreen(
          dbService: widget.dbService,
          existingMeasurement: _currentMeasurement,
          selectedDate: DateTime.now(),
        ),
      ),
    );
    
    if (result == true) {
      _loadData();
    }
  }
  
  Future<void> _importBodyFromHealthConnect() async {
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

    // Always import since the earliest tracking date (or the year-2000 floor
    // when no goal exists yet). The time-period selection dialog was dropped
    // along with the Reports/Activities HC FABs.
    final earliestGoalDate = await NutritionGoalService(widget.dbService).getEarliestGoalDate();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.healthConnectImportingBody)),
    );

    try {
      final end = DateTime.now();
      final start = earliestGoalDate ?? DateTime(2000);
      final imported = await hc.importBodyMeasurements(start: start, end: end);

      if (imported.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.healthConnectNoResultsBody)),
          );
        }
        return;
      }

      final service = UserBodyMeasurementsService(widget.dbService);
      int saved = 0;
      for (final measurement in imported) {
        await service.saveMeasurement(measurement);
        saved++;
      }

      // Auto-adjust nutrition goal and wait for completion so profile reloads with updated goal
      await NutritionGoalService.autoAdjustGoal(widget.dbService);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.healthConnectSuccessBody(saved)),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.healthConnectError(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openGoalRecommendation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GoalRecommendationScreen(
          dbService: widget.dbService,
        ),
      ),
    );
    if (result != null || true) {
      _loadData();
    }
  }

  Widget _buildAccountInfo(BuildContext context) {
    final name = widget.authService.userName;
    final email = widget.authService.userEmail;

    Widget? badge;
    if (AppFeatures.isPaid) {
      badge = const _PlanBadge(label: 'Pro', color: Colors.amber);
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            (name?.isNotEmpty == true ? name![0] : email![0]).toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: name != null && name.isNotEmpty ? Text(name) : null,
        subtitle: email != null ? Text(email) : null,
        trailing: badge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    // Guest mode: show placeholder
    if (widget.isGuestMode) {
      return Scaffold(
        appBar: AppBar(title: Text(l.profileTitle)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                l.guestModeSignIn,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Profile management requires signing in',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.refreshTooltip,
            onPressed: _isLoading ? null : _userRefresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _userRefresh,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 80 + MediaQuery.paddingOf(context).bottom),
              children: [
                // =======================================
                // ACCOUNT INFO
                // =======================================
                _buildAccountInfo(context),
                const SizedBox(height: 8),

                // =======================================
                // ERNÄHRUNGSZIEL
                // =======================================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.flag, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  l.goalCardTitle,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(_goal == null ? Icons.add : Icons.edit),
                              onPressed: _openGoalRecommendation,
                              tooltip: _goal == null ? l.createGoalButton : l.adjustGoal,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_goal == null)
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.flag_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  l.goalEmpty,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _openGoalRecommendation,
                                  icon: const Icon(Icons.add),
                                  label: Text(l.createGoalButton),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          if (!_goal!.macroOnly)
                            _buildDataRow(
                              icon: Icons.local_fire_department,
                              label: l.nutrientCalories,
                              value: '${_goal!.calories.toInt()} kcal',
                              color: Colors.orange,
                            ),
                          _buildDataRow(
                            icon: Icons.egg_alt,
                            label: l.nutrientProtein,
                            value: '${_goal!.protein.toInt()} g',
                            color: Colors.red,
                          ),
                          // Protein-only mode: fat & carbs have no target.
                          if (!_goal!.proteinOnlyEffective) ...[
                            _buildDataRow(
                              icon: Icons.grain,
                              label: l.nutrientCarbs,
                              value: '${_goal!.carbs.toInt()} g',
                              color: Colors.amber,
                            ),
                            _buildDataRow(
                              icon: Icons.opacity,
                              label: l.nutrientFat,
                              value: '${_goal!.fat.toInt()} g',
                              color: Colors.blue,
                            ),
                          ],
                          _buildWaterGoalRow(l),
                          if (WaterReminderService.isSupported)
                            _buildWaterReminderRow(l),
                          if (FoodLogReminderService.isSupported)
                            _buildFoodLogReminderRow(l),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =======================================
                // PROFILDATEN (statisch, selten änderbar)
                // =======================================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  l.profileDataTitle,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(_profile == null ? Icons.add : Icons.edit),
                              onPressed: _editProfile,
                              tooltip: _profile == null ? l.setupProfile : l.editProfile,
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        if (_profile == null)
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.person_outline, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  l.profileDataEmpty,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _editProfile,
                                  icon: const Icon(Icons.add),
                                  label: Text(l.setupProfile),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          // Geburtsdatum & Alter
                          if (_profile!.birthdate != null)
                            _buildDataRow(
                              icon: Icons.cake,
                              label: l.birthdate,
                              value: '${_profile!.birthdate!.day}.${_profile!.birthdate!.month}.${_profile!.birthdate!.year} (${l.ageYears(_profile!.age!)})',
                              color: Colors.purple,
                            ),

                          // Größe
                          if (_profile!.height != null)
                            _buildDataRow(
                              icon: Icons.height,
                              label: l.height,
                              value: '${_profile!.height!.toStringAsFixed(0)} cm',
                              color: Colors.green,
                            ),

                          // Geschlecht
                          if (_profile!.gender != null)
                            _buildDataRow(
                              icon: Icons.wc,
                              label: l.gender,
                              value: _profile!.gender!.localizedName(l),
                              color: Colors.indigo,
                            ),

                          const Divider(height: 24),

                          // Aktivitätslevel
                          if (_profile!.activityLevel != null)
                            _buildDataRow(
                              icon: Icons.directions_run,
                              label: l.activityLevelLabel,
                              value: _profile!.activityLevel!.localizedName(l),
                              color: Colors.teal,
                            ),

                          // Gewichtsziel
                          if (_profile!.weightGoal != null)
                            _buildDataRow(
                              icon: Icons.flag,
                              label: l.weightGoalLabel,
                              value: _profile!.weightGoal!.localizedName(l),
                              color: Colors.amber,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),

                // =======================================
                // DATA SOURCES (Health Connect toggle)
                // Only rendered on platforms where HC is available.
                // =======================================
                if (HealthConnectService.isSupported) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cloud_sync_outlined, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                l.dataSourcesTitle,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _hcImportEnabled,
                            onChanged: _toggleHcImport,
                            title: Text(l.healthConnectToggleTitle),
                            subtitle: Text(l.healthConnectToggleSubtitle),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // =======================================
                // KÖRPERMESSUNGEN (zeitbasiert, regelmäßig)
                // =======================================
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.monitor_weight, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  l.measurementTitle,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (HealthConnectService.isSupported)
                                  IconButton(
                                    icon: const Icon(Icons.health_and_safety_outlined),
                                    tooltip: l.importHealthConnect,
                                    onPressed: _importBodyFromHealthConnect,
                                  ),
                                IconButton(
                                  icon: Icon(_currentMeasurement == null ? Icons.add : Icons.edit),
                                  onPressed: _addOrEditMeasurement,
                                  tooltip: _currentMeasurement == null ? l.addWeight : l.edit,
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        if (_currentMeasurement == null)
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.monitor_weight_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  l.measurementEmpty,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _addOrEditMeasurement,
                                  icon: const Icon(Icons.add),
                                  label: Text(l.addWeight),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          // Gewicht
                          _buildDataRow(
                            icon: Icons.monitor_weight,
                            label: l.weight,
                            value: '${_currentMeasurement!.weight.toStringAsFixed(1)} kg',
                            color: Colors.blue,
                          ),

                          // Körperfett
                          if (_currentMeasurement!.bodyFatPercentage != null)
                            _buildDataRow(
                              icon: Icons.science,
                              label: l.bodyFat,
                              value: '${_currentMeasurement!.bodyFatPercentage!.toStringAsFixed(1)} %',
                              color: Colors.orange,
                            ),

                          // Muskelmasse
                          if (_currentMeasurement!.muscleMassKg != null)
                            _buildDataRow(
                              icon: Icons.fitness_center,
                              label: l.muscleMass,
                              value: '${_currentMeasurement!.muscleMassKg!.toStringAsFixed(1)} kg',
                              color: Colors.red,
                            ),

                          // Taillenumfang
                          if (_currentMeasurement!.waistCm != null)
                            _buildDataRow(
                              icon: Icons.straighten,
                              label: l.waist,
                              value: '${_currentMeasurement!.waistCm!.toStringAsFixed(0)} cm',
                              color: Colors.deepPurple,
                            ),
                          
                          // Messdatum
                          const Divider(height: 24),
                          Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: Text(
                              'Gemessen am: ${_currentMeasurement!.measuredAt.day}.${_currentMeasurement!.measuredAt.month}.${_currentMeasurement!.measuredAt.year}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // =======================================
                // ZEITRAUM-AUSWAHL (gilt für Graph + Liste)
                // =======================================
                if (_currentMeasurement != null) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_MeasurementRange>(
                      segments: [
                        ButtonSegment(value: _MeasurementRange.month1,  label: Text(l.rangeMonth1)),
                        ButtonSegment(value: _MeasurementRange.months3, label: Text(l.rangeMonths3)),
                        ButtonSegment(value: _MeasurementRange.months6, label: Text(l.rangeMonths6)),
                        ButtonSegment(value: _MeasurementRange.year1,   label: Text(l.rangeYear1)),
                        ButtonSegment(value: _MeasurementRange.all,     label: Text(l.rangeAll)),
                      ],
                      selected: {_selectedRange},
                      onSelectionChanged: (set) => _changeRange(set.first),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // =======================================
                // GEWICHTSVERLAUF-GRAPH
                // =======================================
                if (_allMeasurements.length >= 2) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.show_chart, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                l.weightProgress,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
                            child: _buildWeightChart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // =======================================
                // MESSUNGSLISTE
                // =======================================
                if (_allMeasurements.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                l.measurementsSection(_allMeasurements.length),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ..._allMeasurements.map((measurement) => _buildMeasurementTile(context, measurement)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Info-Card
                if (_profile != null && _currentMeasurement != null)
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l.profileInfoText,
                              style: TextStyle(color: Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Upgrade prompt (cloud free users only)
                if (AppConfig.isCloudEdition && !AppFeatures.isPaid) ...[
                  const SizedBox(height: 8),
                  AppFeaturesUtils.buildUpgradePrompt(
                    context,
                    feature: l.upgradeProTitle,
                    description: l.upgradeProProfileDescription,
                  ),
                ],

                // Hilfe & Onboarding-Tour
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.school_outlined, color: Colors.blue),
                    title: Text(l.replayTutorialTitle),
                    subtitle: Text(l.replayTutorialSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Return to the home screen, then replay the tour over it.
                      Navigator.of(context).pop();
                      MainTutorial.requestReplay();
                    },
                  ),
                ),

                // Account & Daten
                const SizedBox(height: 8),
                _AccountSection(
                  dbService: widget.dbService,
                  authService: widget.authService,
                ),
              ],
            ),
            ),
    );
  }
  
  // Displayed water goal — matches overview fallback exactly.
  int get _effectiveWaterGoal => _goal?.waterGoalMl ?? 2000;

  // Smarter suggestion for the edit dialog pre-fill.
  int get _waterGoalSuggestion {
    if (_goal?.waterGoalMl != null) return _goal!.waterGoalMl!;
    if (_currentMeasurement != null) {
      return NutritionCalculator.calculateWaterGoal(_currentMeasurement!.weight);
    }
    return 2000;
  }

  Widget _buildWaterGoalRow(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.water_drop, color: Colors.lightBlue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l.waterTitle,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            '$_effectiveWaterGoal ml',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.lightBlue,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: l.adjustGoal,
            onPressed: () => _editWaterGoal(l),
          ),
        ],
      ),
    );
  }

  Widget _buildWaterReminderRow(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            _waterReminderEnabled
                ? Icons.notifications_active
                : Icons.notifications_off_outlined,
            color: _waterReminderEnabled ? Colors.lightBlue : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.waterReminderTitle,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(l.waterReminderSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        )),
              ],
            ),
          ),
          Switch(
            value: _waterReminderEnabled,
            activeThumbColor: Colors.lightBlue,
            onChanged: (value) {
              // Optimistic update: show the new state immediately
              setState(() => _waterReminderEnabled = value);

              // Then persist it asynchronously
              WaterReminderService.setEnabled(value).then((actual) {
                // If the actual state differs from what we showed, revert
                if (mounted && actual != value) {
                  setState(() => _waterReminderEnabled = actual);
                }
              }).catchError((e) {
                // On error, revert to previous state
                if (mounted) {
                  setState(() => _waterReminderEnabled = !value);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFoodLogReminderRow(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            _foodLogReminderEnabled
                ? Icons.notifications_active
                : Icons.notifications_off_outlined,
            color: _foodLogReminderEnabled ? Colors.orange : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.foodLogReminderTitle,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(l.foodLogReminderSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        )),
              ],
            ),
          ),
          Switch(
            value: _foodLogReminderEnabled,
            activeThumbColor: Colors.orange,
            onChanged: (value) {
              setState(() => _foodLogReminderEnabled = value);
              FoodLogReminderService.setEnabled(value).then((actual) {
                if (mounted && actual != value) {
                  setState(() => _foodLogReminderEnabled = actual);
                }
              }).catchError((e) {
                if (mounted) {
                  setState(() => _foodLogReminderEnabled = !value);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editWaterGoal(AppLocalizations l) async {
    final controller =
        TextEditingController(text: _waterGoalSuggestion.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.water_drop, color: Colors.lightBlue),
            const SizedBox(width: 8),
            Text(l.waterTitle),
          ],
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l.waterGoalFieldLabel,
            helperText: l.waterGoalFieldHint,
            suffixText: 'ml',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.save),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final newValue = int.tryParse(controller.text);
    if (newValue == null || newValue <= 0) return;

    final updatedGoal = NutritionGoal(
      id: _goal?.id,
      userId: _goal?.userId,
      calories: _goal?.calories ?? 0,
      protein: _goal?.protein ?? 0,
      fat: _goal?.fat ?? 0,
      carbs: _goal?.carbs ?? 0,
      validFrom: _goal?.validFrom,
      trackingMethod: _goal?.trackingMethod,
      waterGoalMl: newValue,
    );

    try {
      final saved = await NutritionGoalService(widget.dbService)
          .createOrUpdateGoal(updatedGoal, validFrom: _goal?.validFrom);
      if (mounted) {
        setState(() => _goal = saved);
        DataStore.instance.setGoal(saved); // keep overview in sync
      }
    } catch (_) {}
  }

  Widget _buildDataRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 500;

    if (isMobile) {
      // Mobile: Vertical layout to avoid text wrapping
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop: Horizontal layout
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWeightChart() {
    // Sortiere Messungen chronologisch (älteste zuerst für Graph)
    final sortedMeasurements = List<UserBodyMeasurement>.from(_allMeasurements)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    
    // Erstelle Datenpunkte
    final spots = sortedMeasurements.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.weight);
    }).toList();
    
    // Min/Max für Y-Achse
    final weights = sortedMeasurements.map((m) => m.weight).toList();
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final weightRange = maxWeight - minWeight;
    final yMin = (minWeight - weightRange * 0.1).floorToDouble();
    final yMax = (maxWeight + weightRange * 0.1).ceilToDouble();
    
    // Pre-compute which index "owns" each unique date so only one label
    // renders per date, regardless of the order fl_chart invokes
    // getTitlesWidget (previous Set-mutation-in-callback approach sometimes
    // let adjacent same-day measurements show twice — "1.3. 1.3. 3.3.").
    final multiYear = sortedMeasurements.first.measuredAt.year !=
        sortedMeasurements.last.measuredAt.year;
    String dateKey(DateTime d) => multiYear
        ? '${d.year}-${d.month}-${d.day}'
        : '${d.month}-${d.day}';
    final firstIndexForDate = <String, int>{};
    for (int i = 0; i < sortedMeasurements.length; i++) {
      firstIndexForDate.putIfAbsent(
          dateKey(sortedMeasurements[i].measuredAt), () => i);
    }
    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withValues(alpha: 0.2),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toStringAsFixed(0)}kg',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                // Ignore fractional ticks fl_chart sometimes emits.
                if (value != value.roundToDouble()) return const SizedBox();
                final index = value.toInt();
                final n = sortedMeasurements.length;
                if (index < 0 || index >= n) return const SizedBox();
                final m = sortedMeasurements[index];
                // Only render on the first index of each unique date.
                if (firstIndexForDate[dateKey(m.measuredAt)] != index) {
                  return const SizedBox();
                }
                // Show every k-th unique-date label to avoid crowding.
                final uniqueDateCount = firstIndexForDate.length;
                final k = uniqueDateCount <= 7
                    ? 1
                    : uniqueDateCount <= 15
                        ? 2
                        : uniqueDateCount <= 30
                            ? 3
                            : 5;
                // Position within the deduped date sequence (0, 1, 2, …).
                final datePos = firstIndexForDate.values
                    .toList()
                    .indexOf(index);
                if (datePos % k != 0) return const SizedBox();
                final label = multiYear
                    ? '${m.measuredAt.day}.${m.measuredAt.month}.${m.measuredAt.year % 100}'
                    : '${m.measuredAt.day}.${m.measuredAt.month}.';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (yMax - yMin) / 5,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final measurement = sortedMeasurements[spot.x.toInt()];
                return LineTooltipItem(
                  '${measurement.weight.toStringAsFixed(1)} kg\n${measurement.measuredAt.day}.${measurement.measuredAt.month}.${measurement.measuredAt.year}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
  
  Widget _buildMeasurementTile(BuildContext context, UserBodyMeasurement measurement) {
    final l = AppLocalizations.of(context)!;
    final isLatest = _currentMeasurement?.id == measurement.id;
    
    return Card(
      elevation: isLatest ? 4 : 1,
      color: isLatest ? Colors.blue.shade50 : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isLatest ? Colors.blue : Colors.grey.shade400,
          child: Icon(
            Icons.monitor_weight,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              '${measurement.weight.toStringAsFixed(1)} kg',
              style: TextStyle(
                fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l.latestBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${measurement.measuredAt.day}.${measurement.measuredAt.month}.${measurement.measuredAt.year}'),
            if (measurement.bodyFatPercentage != null ||
                measurement.muscleMassKg != null)
              Text(
                [
                  if (measurement.bodyFatPercentage != null)
                    'KFA: ${measurement.bodyFatPercentage!.toStringAsFixed(1)}%',
                  if (measurement.muscleMassKg != null)
                    'Muskeln: ${measurement.muscleMassKg!.toStringAsFixed(1)}kg',
                ].join(' • '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AddBodyMeasurementScreen(
                      dbService: widget.dbService,
                      existingMeasurement: measurement,
                      selectedDate: measurement.measuredAt,
                    ),
                  ),
                );
                if (result == true) {
                  _loadData();
                }
              },
              tooltip: l.edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final lCtx = AppLocalizations.of(context)!;
                final dateStr = '${measurement.measuredAt.day}.${measurement.measuredAt.month}.${measurement.measuredAt.year}';
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    final ld = AppLocalizations.of(context)!;
                    return AlertDialog(
                      title: Text(ld.deleteMeasurementTitle),
                      content: Text(ld.deleteMeasurementConfirm(dateStr)),
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

                if (confirmed == true && measurement.id != null) {
                  try {
                    final service = UserBodyMeasurementsService(widget.dbService);
                    await service.deleteMeasurement(measurement.id!);

                    // Auto-adjust nutrition goal based on new current measurement
                    await NutritionGoalService.autoAdjustGoal(widget.dbService);

                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(lCtx.measurementDeleted),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadData();
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(lCtx.errorPrefix(e.toString())),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              tooltip: l.delete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account section ──────────────────────────────────────────────────────────

class _AccountSection extends StatefulWidget {
  final NeonDatabaseService dbService;
  final NeonAuthService authService;

  const _AccountSection({required this.dbService, required this.authService});

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _isWorking = false;

  Future<void> _export() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _isWorking = true);
    try {
      await AccountService(widget.dbService).exportAndShare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.exportDataError(e.toString())),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteAccount() async {
    final l = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(ld.deleteAccountConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ld.deleteAccountConfirmText),
              const SizedBox(height: 12),
              Text(
                ld.deleteAccountCredentialsHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ld.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(ld.deleteAccountConfirmButton),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await AccountService(widget.dbService).deleteAllUserData();
      await widget.authService.deleteAuthUser();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.deleteAccountError(e.toString())),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.accountSectionTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined, color: Colors.blue),
              title: Text(l.exportDataButton),
              subtitle: Text(l.exportDataDescription),
              trailing: _isWorking
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isWorking ? null : _export,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade600),
              title: Text(
                l.deleteAccountButton,
                style: TextStyle(color: Colors.red.shade700),
              ),
              subtitle: Text(l.deleteAccountDescription),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isWorking ? null : _deleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PlanBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(160)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color == Colors.amber ? Colors.amber.shade800 : Colors.blue.shade700,
        ),
      ),
    );
  }
}
