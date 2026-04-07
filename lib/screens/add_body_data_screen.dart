import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_body_data.dart';
import '../services/user_body_data_service.dart';
import '../services/neon_database_service.dart';
import '../services/app_logger.dart';

/// Screen zum Eingeben/Bearbeiten von Körperdaten
class AddBodyDataScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final UserBodyData? existingData;  // Für Bearbeiten
  final DateTime selectedDate;
  
  const AddBodyDataScreen({
    super.key,
    required this.dbService,
    this.existingData,
    required this.selectedDate,
  });
  
  @override
  State<AddBodyDataScreen> createState() => _AddBodyDataScreenState();
}

class _AddBodyDataScreenState extends State<AddBodyDataScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  late TextEditingController _ageController;
  
  late Gender _selectedGender;
  late ActivityLevel _selectedActivityLevel;
  late WeightGoal _selectedWeightGoal;
  bool _isSaving = false;
  
  @override
  void initState() {
    super.initState();
    
    // Initialisiere Controller (entweder leer oder mit existierenden Werten)
    final data = widget.existingData;
    
    _weightController = TextEditingController(
      text: data?.weight.toStringAsFixed(1) ?? '',
    );
    _heightController = TextEditingController(
      text: data?.height.toStringAsFixed(0) ?? '',
    );
    _ageController = TextEditingController(
      text: data?.age.toString() ?? '',
    );
    
    _selectedGender = data?.gender ?? Gender.male;
    _selectedActivityLevel = data?.activityLevel ?? ActivityLevel.moderate;
    _selectedWeightGoal = data?.weightGoal ?? WeightGoal.maintain;
  }
  
  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    super.dispose();
  }
  
  Future<void> _saveBodyData() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      final bodyData = UserBodyData(
        id: widget.existingData?.id,
        weight: double.parse(_weightController.text),
        height: double.parse(_heightController.text),
        age: int.parse(_ageController.text),
        gender: _selectedGender,
        activityLevel: _selectedActivityLevel,
        weightGoal: _selectedWeightGoal,
      );
      
      final service = UserBodyDataService(widget.dbService);
      await service.saveBodyData(
        bodyData, 
        measuredAt: widget.selectedDate,
        calculateMetrics: true,  // Berechne BMR/TDEE automatisch
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingData == null 
                  ? '✅ Körperdaten gespeichert!' 
                  : '✅ Änderungen gespeichert!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
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
    final isEdit = widget.existingData != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Körperdaten bearbeiten' : 'Körperdaten eingeben'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info-Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Diese Daten werden für personalisierte Empfehlungen und Kalorien-Schätzungen verwendet.',
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Gewicht (Pflichtfeld)
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(
                labelText: 'Gewicht *',
                suffixText: 'kg',
                border: OutlineInputBorder(),
                helperText: 'Erforderlich für Kalorien-Schätzung',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte Gewicht eingeben';
                }
                final weight = double.tryParse(value);
                if (weight == null || weight <= 0 || weight > 300) {
                  return 'Ungültiges Gewicht';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Größe (Pflichtfeld)
            TextFormField(
              controller: _heightController,
              decoration: const InputDecoration(
                labelText: 'Größe *',
                suffixText: 'cm',
                border: OutlineInputBorder(),
                helperText: 'Für BMI & BMR-Berechnung',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte Größe eingeben';
                }
                final height = double.tryParse(value);
                if (height == null || height < 100 || height > 250) {
                  return 'Ungültige Größe (100-250cm)';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Alter (Pflichtfeld)
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(
                labelText: 'Alter *',
                suffixText: 'Jahre',
                border: OutlineInputBorder(),
                helperText: 'Für BMR-Berechnung',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte Alter eingeben';
                }
                final age = int.tryParse(value);
                if (age == null || age < 10 || age > 120) {
                  return 'Ungültiges Alter (10-120)';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Geschlecht
            DropdownButtonFormField<Gender>(
              initialValue: _selectedGender,
              decoration: const InputDecoration(
                labelText: 'Geschlecht',
                border: OutlineInputBorder(),
                helperText: 'Für genauere BMR-Berechnung',
              ),
              items: Gender.values.map((gender) {
                return DropdownMenuItem(
                  value: gender,
                  child: Text(gender.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedGender = value;
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Activity Level
            DropdownButtonFormField<ActivityLevel>(
              initialValue: _selectedActivityLevel,
              decoration: const InputDecoration(
                labelText: 'Aktivitätslevel',
                border: OutlineInputBorder(),
                helperText: 'Durchschnittliche tägliche Aktivität',
              ),
              items: ActivityLevel.values.map((level) {
                return DropdownMenuItem(
                  value: level,
                  child: Text(level.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedActivityLevel = value;
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Weight Goal
            DropdownButtonFormField<WeightGoal>(
              initialValue: _selectedWeightGoal,
              decoration: const InputDecoration(
                labelText: 'Gewichtsziel',
                border: OutlineInputBorder(),
                helperText: 'Was ist dein Ziel?',
              ),
              items: WeightGoal.values.map((goal) {
                return DropdownMenuItem(
                  value: goal,
                  child: Text(goal.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedWeightGoal = value;
                  });
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            // Speichern Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveBodyData,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? 'Speichere...' : 'Speichern'),
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

