import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import 'package:flutter/services.dart';
import '../models/user_body_data.dart';
import '../services/user_body_measurements_service.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../l10n/app_localizations.dart';

/// Screen zum Eingeben von zeitbasierten Körpermessungen (Gewicht, etc.)
class AddBodyMeasurementScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final UserBodyMeasurement? existingMeasurement;
  final DateTime selectedDate;

  const AddBodyMeasurementScreen({
    super.key,
    required this.dbService,
    this.existingMeasurement,
    required this.selectedDate,
  });

  @override
  State<AddBodyMeasurementScreen> createState() => _AddBodyMeasurementScreenState();
}

class _AddBodyMeasurementScreenState extends State<AddBodyMeasurementScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _weightController;
  late TextEditingController _bodyFatController;
  late TextEditingController _muscleMassController;
  late TextEditingController _waistController;
  late TextEditingController _notesController;

  late DateTime _selectedDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _selectedDate = widget.selectedDate;
    final m = widget.existingMeasurement;

    _weightController = TextEditingController(
      text: m?.weight.toStringAsFixed(1) ?? '',
    );
    _bodyFatController = TextEditingController(
      text: m?.bodyFatPercentage?.toStringAsFixed(1) ?? '',
    );
    _muscleMassController = TextEditingController(
      text: m?.muscleMassKg?.toStringAsFixed(1) ?? '',
    );
    _waistController = TextEditingController(
      text: m?.waistCm?.toStringAsFixed(0) ?? '',
    );
    _notesController = TextEditingController(
      text: m?.notes ?? '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _bodyFatController.dispose();
    _muscleMassController.dispose();
    _waistController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveMeasurement() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final measurement = UserBodyMeasurement(
        id: widget.existingMeasurement?.id,
        weight: parseDouble(_weightController.text),
        bodyFatPercentage: _bodyFatController.text.isNotEmpty
            ? parseDouble(_bodyFatController.text)
            : null,
        muscleMassKg: _muscleMassController.text.isNotEmpty
            ? parseDouble(_muscleMassController.text)
            : null,
        waistCm: _waistController.text.isNotEmpty
            ? parseDouble(_waistController.text)
            : null,
        measuredAt: _selectedDate,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      final service = UserBodyMeasurementsService(widget.dbService);
      await service.saveMeasurement(measurement);

      // Auto-adjust nutrition goal and wait for completion so profile reloads with updated goal
      await NutritionGoalService.autoAdjustGoal(widget.dbService);

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.measurementSaved),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.errorPrefix(e.toString())),
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
    final isEdit = widget.existingMeasurement != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.editMeasurementTitle : l.addMeasurementTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Info
            Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.teal.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.profileInfoText,
                        style: TextStyle(color: Colors.teal.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Datum-Auswahl
            Card(
              elevation: 2,
              child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.blue.shade700),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.measurementDate,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.edit, color: Colors.grey.shade400, size: 20),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Gewicht (Pflicht)
            TextFormField(
              controller: _weightController,
              decoration: InputDecoration(
                labelText: '${l.weight} *',
                suffixText: 'kg',
                border: const OutlineInputBorder(),
                helperText: l.requiredField,
                prefixIcon: const Icon(Icons.monitor_weight),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.weightRequired;
                }
                final weight = tryParseDouble(value);
                if (weight == null || weight <= 0 || weight > 300) {
                  return l.weightInvalid;
                }
                return null;
              },
              autofocus: true,
            ),

            const SizedBox(height: 24),

            // Optional: Erweiterte Messungen
            ExpansionTile(
              title: Text(l.advancedOptional),
              initiallyExpanded: isEdit && (
                widget.existingMeasurement!.bodyFatPercentage != null ||
                widget.existingMeasurement!.muscleMassKg != null
              ),
              children: [
                const SizedBox(height: 16),

                // Körperfett
                TextFormField(
                  controller: _bodyFatController,
                  decoration: InputDecoration(
                    labelText: l.bodyFatOptional,
                    suffixText: '%',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.science),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                  ],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final fat = tryParseDouble(value);
                      if (fat == null || fat < 0 || fat > 50) {
                        return l.bodyFatInvalid;
                      }
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Muskelmasse
                TextFormField(
                  controller: _muscleMassController,
                  decoration: InputDecoration(
                    labelText: l.muscleOptional,
                    suffixText: 'kg',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.fitness_center),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                  ],
                ),

                const SizedBox(height: 16),

                // Taillenumfang
                TextFormField(
                  controller: _waistController,
                  decoration: InputDecoration(
                    labelText: l.waistOptional,
                    suffixText: 'cm',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.straighten),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),

            const SizedBox(height: 16),

            // Notizen
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.notesOptional,
                border: const OutlineInputBorder(),
                hintText: l.notesHint,
                prefixIcon: const Icon(Icons.note),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            // Speichern Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveMeasurement,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? l.saving : l.save),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
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
