import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/physical_activity.dart';
import '../models/activity_item.dart';
import '../services/activity_database_service.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';

/// Screen zum Bearbeiten einer Aktivität
class EditActivityScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final PhysicalActivity activity;
  
  const EditActivityScreen({
    super.key,
    required this.dbService,
    required this.activity,
  });
  
  @override
  State<EditActivityScreen> createState() => _EditActivityScreenState();
}

class _EditActivityScreenState extends State<EditActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _durationController;
  late TextEditingController _caloriesController;
  late TextEditingController _distanceController;
  late TextEditingController _notesController;
  
  ActivityItem? _selectedActivity;
  List<ActivityItem> _availableActivities = [];  // Neu: Liste aus DB
  late TimeOfDay _startTime;
  bool _isSaving = false;
  bool _isLoadingActivities = true;  // Neu: Loading-State
  
  @override
  void initState() {
    super.initState();
    
    _startTime = TimeOfDay.fromDateTime(widget.activity.startTime);
    
    _durationController = TextEditingController(
      text: (widget.activity.durationMinutes ?? widget.activity.calculatedDuration).toString(),
    );
    _caloriesController = TextEditingController(
      text: widget.activity.caloriesBurned?.toStringAsFixed(0) ?? '',
    );
    _distanceController = TextEditingController(
      text: widget.activity.distanceKm?.toStringAsFixed(1) ?? '',
    );
    _notesController = TextEditingController(
      text: widget.activity.notes ?? '',
    );
    
    // Lade Activities aus DB
    _loadActivities();
  }
  
  /// Lade alle Activities aus Datenbank
  Future<void> _loadActivities() async {
    try {
      final service = ActivityDatabaseService(widget.dbService);
      final publicActivities = await service.getPublicActivities();
      final myActivities = await service.getMyActivities();
      
      if (!mounted) return;
      
      setState(() {
        _availableActivities = [...myActivities, ...publicActivities];
        _isLoadingActivities = false;
        
        // Versuche die ursprüngliche Activity zu finden (falls aus DB)
        if (widget.activity.activityId != null) {
          _selectedActivity = _availableActivities.firstWhere(
            (a) => a.id == widget.activity.activityId,
            orElse: () => _availableActivities.first,
          );
        } else {
          // Keine DB-Activity, verwende erste als Default
          _selectedActivity = _availableActivities.isNotEmpty ? _availableActivities.first : null;
        }
      });
      
      print('✅ ${_availableActivities.length} Activities für Edit geladen');
    } catch (e) {
      print('❌ Fehler beim Laden der Activities: $e');
      if (mounted) {
        setState(() {
          _isLoadingActivities = false;
        });
      }
    }
  }
  
  @override
  void dispose() {
    _durationController.dispose();
    _caloriesController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
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
  
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Kombiniere Datum + neue Uhrzeit
      final originalDate = widget.activity.startTime;
      final startDateTime = DateTime(
        originalDate.year,
        originalDate.month,
        originalDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      
      final durationMinutes = int.parse(_durationController.text);
      final endDateTime = startDateTime.add(Duration(minutes: durationMinutes));
      
      final updatedActivity = PhysicalActivity(
        id: widget.activity.id,
        activityType: ActivityType.other,
        activityId: _selectedActivity?.id,
        activityName: _selectedActivity?.name,
        startTime: startDateTime,
        endTime: endDateTime,
        durationMinutes: durationMinutes,
        caloriesBurned: _caloriesController.text.isNotEmpty 
            ? double.parse(_caloriesController.text) 
            : null,
        distanceKm: _distanceController.text.isNotEmpty 
            ? double.parse(_distanceController.text) 
            : null,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        source: widget.activity.source,  // Behalte Original-Source
        healthConnectRecordId: widget.activity.healthConnectRecordId,
      );
      
      // Optimistic update — immediately visible in all tabs.
      DataStore.instance.replaceActivity(updatedActivity);

      final saved = await SyncService.instance.updateActivity(updatedActivity);
      if (saved != null) DataStore.instance.replaceActivity(saved);

      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.entryUpdated),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Fehler beim Speichern: $e');

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
        title: Text(l.editMeasurementTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Aktivität aus Datenbank wählen
            if (_isLoadingActivities)
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
            else if (_availableActivities.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.activitiesEmpty),
                ),
              )
            else
              DropdownButtonFormField<ActivityItem>(
                value: _selectedActivity,
                decoration: const InputDecoration(
                  labelText: 'Aktivität',
                  border: OutlineInputBorder(),
                  helperText: '🌍 öffentlich  🕐 ausstehend  👤 privat',
                ),
                isExpanded: true,
                items: _availableActivities.map((activity) {
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
                    setState(() {
                      _selectedActivity = value;
                    });
                  }
                },
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

            // Kalorien
            TextFormField(
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Kalorien (optional)',
                suffixText: 'kcal',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Distanz
            if (_selectedActivity?.avgSpeedKmh != null) ...[
              TextFormField(
                controller: _distanceController,
                decoration: const InputDecoration(
                  labelText: 'Distanz (optional)',
                  suffixText: 'km',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
              ),
              const SizedBox(height: 16),
            ],
            
            // Notizen
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 24),
            
            // Speichern Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? l.saving : l.save),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
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

