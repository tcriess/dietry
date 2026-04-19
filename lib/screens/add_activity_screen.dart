import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import 'package:flutter/services.dart';
import '../models/physical_activity.dart';
import '../models/activity_item.dart';
import '../services/user_body_measurements_service.dart';
import '../services/activity_database_service.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/local_data_service.dart';
import '../services/app_logger.dart';
import '../services/anonymous_auth_service.dart';
import '../app_config.dart';
import '../l10n/app_localizations.dart';
import 'activity_database_screen.dart';

/// Screen zum Hinzufügen einer Aktivität
class AddActivityScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime selectedDate;

  const AddActivityScreen({
    super.key,
    this.dbService,
    required this.selectedDate,
  });
  
  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _distanceController = TextEditingController();
  final _notesController = TextEditingController();
  final _metValueController = TextEditingController();
  
  ActivityItem? _selectedActivity;
  List<ActivityItem> _searchResults = [];
  String? _lastAutoCalcCalories;  // Letzter automatisch berechneter Kalorienwert
  
  TimeOfDay _startTime = TimeOfDay.now();
  bool _isSaving = false;
  double? _userWeight;  // ✅ Nur Gewicht speichern (von Measurement)
  
  @override
  void initState() {
    super.initState();
    _loadWeight();
    _loadActivities();  // Lade Activities aus DB
    
    // Listener für Dauer-Änderungen → Auto-Kalorien-Berechnung
    _durationController.addListener(_calculateCaloriesIfNeeded);
  }
  
  /// Lade alle Activities (public + eigene) aus Datenbank
  Future<void> _loadActivities() async {
    try {
      if (widget.dbService == null) {
        // Guest mode: try to load public activities with anonymous token
        appLogger.d('ℹ️ Guest mode: Trying to load public activities with anonymous token');

        final anonToken = await AnonymousAuthService.getToken(AppConfig.authBaseUrl);
        if (anonToken != null) {
          // Create temporary NeonDatabaseService with anonymous token
          final anonDbService = NeonDatabaseService();
          await anonDbService.init();
          await anonDbService.setJWT(anonToken);

          final service = ActivityDatabaseService(anonDbService);
          final publicActivities = await service.getPublicActivities();

          if (!mounted) return;

          setState(() {
            _searchResults = publicActivities;
          });

          appLogger.i('✅ ${publicActivities.length} public activities loaded in guest mode');
        } else {
          appLogger.w('⚠️ Anonymous token unavailable, showing manual entry only');
          if (mounted) {
            setState(() {
              _searchResults = [];
            });
          }
        }
        return;
      }

      final service = ActivityDatabaseService(widget.dbService!);

      // Hole public Activities + eigene private Activities
      final publicActivities = await service.getPublicActivities();
      final myActivities = await service.getMyActivities();

      if (!mounted) return;

      setState(() {
        // Kombiniere: Eigene zuerst, dann public
        _searchResults = [...myActivities, ...publicActivities];
      });

      appLogger.i('✅ ${_searchResults.length} Activities aus DB geladen');
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Activities: $e');
    }
  }
  
  Future<void> _loadWeight() async {
    try {
      // In guest mode (no dbService), load weight from local database
      if (widget.dbService == null) {
        appLogger.d('ℹ️ Guest mode: Loading weight from local database');
        final local = LocalDataService.instance;
        final measurement = await local.getCurrentMeasurement();

        if (!mounted) return;

        setState(() {
          _userWeight = measurement?.weight;
        });

        if (_userWeight != null) {
          appLogger.i('✅ Gewicht geladen (lokal): ${_userWeight!.toStringAsFixed(1)}kg');
          _calculateCaloriesIfNeeded();
        } else {
          appLogger.w('⚠️ Kein Gewicht im lokalen Speicher - Kalorien müssen manuell eingegeben werden');
        }
        return;
      }

      final service = UserBodyMeasurementsService(widget.dbService!);
      final measurement = await service.getCurrentMeasurement();

      if (!mounted) return;

      setState(() {
        _userWeight = measurement?.weight;
      });

      if (_userWeight != null) {
        appLogger.i('✅ Gewicht geladen: ${_userWeight!.toStringAsFixed(1)}kg');
        // Trigger initiale Berechnung wenn Dauer schon eingegeben wurde
        _calculateCaloriesIfNeeded();
      } else {
        appLogger.w('⚠️ Kein Gewicht in DB - Kalorien müssen manuell eingegeben werden');
      }
    } catch (e) {
      appLogger.e('❌ Konnte Gewicht nicht laden: $e');
    }
  }
  
  /// Berechne Kalorien automatisch.
  ///
  /// Überschreibt den Wert nur wenn:
  /// - Das Feld leer ist, ODER
  /// - Der aktuelle Wert dem letzten auto-berechneten Wert entspricht
  ///   (d.h. der User hat ihn nicht manuell geändert).
  void _calculateCaloriesIfNeeded() {
    if (_durationController.text.isEmpty) return;
    if (_userWeight == null) return;
    if (_selectedActivity == null) return;

    final currentText = _caloriesController.text;
    // Nicht überschreiben wenn User einen eigenen Wert eingetragen hat
    if (currentText.isNotEmpty && currentText != _lastAutoCalcCalories) return;

    final durationMinutes = int.tryParse(_durationController.text);
    if (durationMinutes == null || durationMinutes <= 0) return;

    final calories = _selectedActivity!.metValue * _userWeight! * (durationMinutes / 60.0);
    _lastAutoCalcCalories = calories.toStringAsFixed(0);

    _caloriesController.value = TextEditingValue(
      text: _lastAutoCalcCalories!,
      selection: TextSelection.collapsed(offset: _lastAutoCalcCalories!.length),
    );
  }
  
  /// Wähle Activity aus Suchergebnissen oder Datenbank
  void _selectActivity(ActivityItem activity) {
    _lastAutoCalcCalories = null;  // Bei Aktivitätswechsel Sperre aufheben
    setState(() {
      _selectedActivity = activity;
      _nameController.text = activity.name;
      _metValueController.text = activity.metValue.toStringAsFixed(1);
    });
    _calculateCaloriesIfNeeded();
  }
  
  @override
  void dispose() {
    _durationController.removeListener(_calculateCaloriesIfNeeded);
    _nameController.dispose();
    _durationController.dispose();
    _caloriesController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
    _metValueController.dispose();
    super.dispose();
  }
  
  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    
    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }
  
  Future<void> _saveActivity() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Kombiniere Datum + Uhrzeit
      final startDateTime = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );

      final durationMinutes = int.parse(_durationController.text);
      final endDateTime = startDateTime.add(Duration(minutes: durationMinutes));

      final activity = PhysicalActivity(
        activityType: ActivityType.other,
        activityId: _selectedActivity?.id,
        activityName: _selectedActivity?.name,
        startTime: startDateTime,
        endTime: endDateTime,
        durationMinutes: durationMinutes,
        caloriesBurned: _caloriesController.text.isNotEmpty
            ? parseDouble(_caloriesController.text)
            : null,
        distanceKm: _distanceController.text.isNotEmpty
            ? parseDouble(_distanceController.text)
            : null,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        source: DataSource.manual,
      );

      final saved = await SyncService.instance.saveActivity(activity);
      // Add the server entity (real id) or the optimistic entry (queued offline).
      DataStore.instance.addActivity(saved ?? activity);

      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.measurementSaved),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern: $e');

      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.errorPrefix(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.addActivity),
        actions: [
          if (widget.dbService != null)
            IconButton(
              icon: const Icon(Icons.storage_outlined),
              tooltip: l.myActivities,
              onPressed: () async {
                final activity = await Navigator.of(context).push<ActivityItem>(
                  MaterialPageRoute(
                    builder: (context) => ActivityDatabaseScreen(dbService: widget.dbService!),
                  ),
                );
                if (activity != null && mounted) {
                  _selectActivity(activity);
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Aktivität aus Datenbank wählen
            if (_searchResults.isNotEmpty)
              // Show dropdown if activities are available (both authenticated and guest mode)
              DropdownButtonFormField<ActivityItem>(
                initialValue: _selectedActivity,
                decoration: const InputDecoration(
                  labelText: 'Aktivität',
                  border: OutlineInputBorder(),
                  helperText: '🌍 öffentlich  🕐 ausstehend  👤 privat',
                ),
                isExpanded: true,
                items: _searchResults.map((activity) {
                  final statusIcon = !activity.isPublic
                      ? '👤'
                      : activity.isApproved
                          ? '🌍'
                          : '🕐';
                  return DropdownMenuItem(
                    value: activity,
                    child: Row(
                      children: [
                        Text(activity.categoryIcon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activity.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(statusIcon, style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _lastAutoCalcCalories = null;  // Bei Aktivitätswechsel Sperre aufheben
                    setState(() {
                      _selectedActivity = value;
                      _nameController.text = value.name;
                      _metValueController.text = value.metValue.toStringAsFixed(1);
                    });
                    _calculateCaloriesIfNeeded();
                  }
                },
              )
            else if (widget.dbService != null)
              // Show loading spinner in authenticated mode
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 16),
                      Text(l.loading),
                    ],
                  ),
                ),
              )
            else
              // In guest mode with no anonymous token: show note about manual entry
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'In guest mode, enter activities manually below',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Button: Eigene Aktivität zur Datenbank hinzufügen (only in authenticated mode)
            if (widget.dbService != null)
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final lCtx = AppLocalizations.of(context)!;
                  final result = await showDialog<ActivityItem>(
                    context: context,
                    builder: (context) => const ActivityEditDialog(
                      activity: null,
                      isEditing: false,
                    ),
                  );

                  if (result != null) {
                    try {
                      final service = ActivityDatabaseService(widget.dbService!);
                      final created = await service.createActivity(result);

                      if (mounted) {
                        await _loadActivities();

                        setState(() {
                          _selectedActivity = created;
                          _nameController.text = created.name;
                          _metValueController.text = created.metValue.toStringAsFixed(1);
                        });

                        _calculateCaloriesIfNeeded();

                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(lCtx.foodAdded(created.name)),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
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
                icon: const Icon(Icons.add_circle_outline),
                label: Text(l.saveToDatabase),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Startzeit
            InkWell(
              onTap: _selectStartTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Startzeit',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.access_time),
                ),
                child: Text(_startTime.format(context)),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Dauer
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(
                labelText: 'Dauer',
                suffixText: 'Minuten',
                border: OutlineInputBorder(),
                helperText: 'Wie lange war die Aktivität?',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.requiredField;
                }
                final duration = int.tryParse(value);
                if (duration == null || duration <= 0) {
                  return l.weightInvalid;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Kalorien (optional, automatisch berechnet)
            TextFormField(
              controller: _caloriesController,
              decoration: InputDecoration(
                labelText: 'Kalorien (optional)',
                suffixText: 'kcal',
                border: const OutlineInputBorder(),
                helperText: _userWeight != null 
                    ? 'Wird automatisch geschätzt (${_userWeight!.toStringAsFixed(0)}kg)'
                    : 'Geschätzte verbrannte Kalorien',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Distanz (optional, nur für Aktivitäten mit Geschwindigkeit)
            if (_selectedActivity?.avgSpeedKmh != null) ...[
              TextFormField(
                controller: _distanceController,
                decoration: const InputDecoration(
                  labelText: 'Distanz (optional)',
                  suffixText: 'km',
                  border: OutlineInputBorder(),
                  helperText: 'Zurückgelegte Distanz',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                ],
              ),
              const SizedBox(height: 16),
            ],
            
            // Notizen (optional)
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
                border: OutlineInputBorder(),
                hintText: 'z.B. Ort, Intensität, Besonderheiten...',
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 24),
            
            // Speichern Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveActivity,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? l.saving : l.save),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

