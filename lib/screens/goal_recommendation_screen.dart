import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/nutrition_calculator.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../services/user_profile_service.dart';
import '../services/user_body_measurements_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import 'tracking_method_screen.dart';

/// Screen zur Eingabe von Körperdaten und Berechnung von Nutrition Goal Empfehlungen
class GoalRecommendationScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const GoalRecommendationScreen({
    super.key,
    required this.dbService,
  });

  @override
  State<GoalRecommendationScreen> createState() => _GoalRecommendationScreenState();
}

class _GoalRecommendationScreenState extends State<GoalRecommendationScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form-Controller
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  DateTime? _birthdate;

  Gender _gender = Gender.male;
  ActivityLevel _activityLevel = ActivityLevel.moderate;
  WeightGoal _weightGoal = WeightGoal.lose;
  
  MacroRecommendation? _recommendation;
  int _waterGoalMl = 2000;
  final _waterGoalController = TextEditingController(text: '2000');
  bool _isCalculating = false;
  bool _isSaving = false;
  bool _isLoadingProfile = true;
  bool _macroOnly = false;
  UserBodyData? _currentBodyData;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final profileService = UserProfileService(widget.dbService);
      final measurementService = UserBodyMeasurementsService(widget.dbService);

      final results = await Future.wait([
        profileService.getCurrentProfile(),
        measurementService.getCurrentMeasurement(),
      ]);

      final profile = results[0] as UserProfile?;
      final measurement = results[1] as UserBodyMeasurement?;

      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
          if (profile != null) {
            if (profile.birthdate != null) _birthdate = profile.birthdate;
            if (profile.height != null) _heightController.text = profile.height!.toStringAsFixed(0);
            if (profile.gender != null) _gender = profile.gender!;
            if (profile.activityLevel != null) _activityLevel = profile.activityLevel!;
            if (profile.weightGoal != null) _weightGoal = profile.weightGoal!;
          }
          if (measurement != null) {
            _weightController.text = measurement.weight.toStringAsFixed(1);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _waterGoalController.dispose();
    super.dispose();
  }

  int? _ageFromBirthdate() {
    if (_birthdate == null) return null;
    final today = DateTime.now();
    int age = today.year - _birthdate!.year;
    if (today.month < _birthdate!.month ||
        (today.month == _birthdate!.month && today.day < _birthdate!.day)) {
      age--;
    }
    return age;
  }

  void _calculateRecommendation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_birthdate == null) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.birthdateSelectSnackbar), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isCalculating = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final bodyData = UserBodyData(
        weight: double.parse(_weightController.text),
        height: double.parse(_heightController.text),
        gender: _gender,
        age: _ageFromBirthdate()!,
        activityLevel: _activityLevel,
        weightGoal: _weightGoal,
      );

      setState(() {
        _isCalculating = false;
      });

      MacroRecommendation? recommendation;

      if (_macroOnly) {
        // Macro-only mode: use tdeeComplete directly without method selection
        appLogger.d('📊 Macro-only mode: Verwende tdeeComplete automatisch');
        recommendation = NutritionCalculator.calculateMacros(bodyData, method: TrackingMethod.tdeeComplete);
      } else {
        // Normal mode: open tracking method screen for user to choose
        recommendation = await Navigator.of(context).push<MacroRecommendation>(
          MaterialPageRoute(
            builder: (_) => TrackingMethodScreen(
              userData: bodyData,
              onRecommendationSelected: (rec) {
                Navigator.of(context).pop(rec);
              },
            ),
          ),
        );
      }

      if (recommendation != null) {
        final autoWater = NutritionCalculator.calculateWaterGoal(bodyData.weight);
        setState(() {
          _recommendation = recommendation;
          _currentBodyData = bodyData;
          _waterGoalMl = autoWater;
          _waterGoalController.text = autoWater.toString();
        });

        appLogger.i('✅ Empfehlung berechnet: ${recommendation.calories.toInt()} kcal');
        appLogger.i('   Methode: ${recommendation.method.displayName}');
      }
    } catch (e) {
      setState(() {
        _isCalculating = false;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('Fehler bei Berechnung: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveGoal() async {
    appLogger.d('');
    appLogger.d('═══════════════════════════════════════');
    appLogger.d('🚀 _saveGoal() GESTARTET');
    appLogger.d('═══════════════════════════════════════');
    appLogger.d('📊 Status:');
    appLogger.d('   - _recommendation: ${_recommendation != null ? "✅ vorhanden" : "❌ NULL"}');
    appLogger.d('   - _currentBodyData: ${_currentBodyData != null ? "✅ vorhanden" : "❌ NULL"}');
    appLogger.d('   - _isSaving: $_isSaving');

    if (_recommendation == null) {
      appLogger.d('');
      appLogger.d('❌ ABBRUCH: _recommendation ist NULL!');
      appLogger.d('═══════════════════════════════════════');
      return;
    }

    if (_currentBodyData == null) {
      appLogger.d('');
      appLogger.d('❌ ABBRUCH: _currentBodyData ist NULL!');
      appLogger.d('═══════════════════════════════════════');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      appLogger.d('');
      appLogger.d('🏗️  Erstelle NutritionGoal aus Recommendation...');
      final baseGoal = NutritionCalculator.createGoalFromRecommendation(_recommendation!);
      final goal = NutritionGoal(
        calories: baseGoal.calories,
        protein: baseGoal.protein,
        fat: baseGoal.fat,
        carbs: baseGoal.carbs,
        trackingMethod: baseGoal.trackingMethod,
        waterGoalMl: _waterGoalMl,
        macroOnly: _macroOnly,
      );
      appLogger.d('   ✅ Goal erstellt:');
      appLogger.d('      - Kalorien: ${goal.calories.toInt()} kcal');
      appLogger.d('      - Protein: ${goal.protein.toInt()}g');
      appLogger.d('      - Fett: ${goal.fat.toInt()}g');
      appLogger.d('      - Kohlenhydrate: ${goal.carbs.toInt()}g');
      appLogger.d('      - Wasserziel: ${goal.waterGoalMl} ml');

      appLogger.d('');
      appLogger.d('🔧 Erstelle NutritionGoalService...');
      final goalService = NutritionGoalService(widget.dbService);
      appLogger.d('   ✅ Service bereit');

      appLogger.d('');
      appLogger.d('💾 SPEICHERE Goal in Datenbank...');
      await goalService.createOrUpdateGoal(goal);
      appLogger.d('   ✅✅✅ GOAL ERFOLGREICH GESPEICHERT! ✅✅✅');

      // Always save profile + measurement alongside goal
      if (_birthdate != null) {
        try {
          final profileService = UserProfileService(widget.dbService);
          final measurementService = UserBodyMeasurementsService(widget.dbService);
          final profile = UserProfile(
            birthdate: _birthdate,
            height: _currentBodyData!.height,
            gender: _currentBodyData!.gender,
            activityLevel: _currentBodyData!.activityLevel,
            weightGoal: _currentBodyData!.weightGoal,
          );
          await profileService.updateProfile(profile);
          final measurement = UserBodyMeasurement(
            weight: _currentBodyData!.weight,
            measuredAt: DateTime.now(),
          );
          await measurementService.saveMeasurement(measurement);
        } catch (e) {
          // Not critical — goal was saved
        }
      }

      appLogger.d('');
      appLogger.d('═══════════════════════════════════════');
      appLogger.d('✅ SPEICHERUNG ERFOLGREICH ABGESCHLOSSEN');
      appLogger.d('═══════════════════════════════════════');
      appLogger.d('');

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.goalSaved),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Show success dialog with option to go back
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final ld = AppLocalizations.of(context)!;
            return AlertDialog(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
              title: Text(ld.goalSavedDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ld.goalSavedDialogContent),
                  const SizedBox(height: 16),
                  if (!_macroOnly)
                    Text(
                      ld.goalTargetLine(goal.calories.toInt()),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  Text('${ld.nutrientProtein}: ${goal.protein.toInt()}g'),
                  Text('${ld.nutrientFat}: ${goal.fat.toInt()}g'),
                  Text('${ld.nutrientCarbs}: ${goal.carbs.toInt()}g'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  child: Text(ld.toOverview),
                ),
              ],
            );
          },
        );
      }
    } catch (e, stackTrace) {
      appLogger.e('❌ Fehler beim Speichern des Goals: $e');
      appLogger.e('   Stack trace: $stackTrace');

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.errorPrefix(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
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
        title: Text(l.goalRecTitle),
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intro
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            l.personalizedRecTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.personalizedRecDesc,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Körperdaten
              Text(
                l.bodyDataTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Gewicht
              TextFormField(
                controller: _weightController,
                decoration: InputDecoration(
                  labelText: l.weightLabel,
                  suffixText: 'kg',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.monitor_weight),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.weightRequired;
                  }
                  final weight = double.tryParse(value);
                  if (weight == null || weight < 30 || weight > 300) {
                    return l.weightInvalidRec;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Größe
              TextFormField(
                controller: _heightController,
                decoration: InputDecoration(
                  labelText: l.heightRecLabel,
                  suffixText: 'cm',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.height),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.requiredField;
                  }
                  final height = int.tryParse(value);
                  if (height == null || height < 100 || height > 250) {
                    return l.heightRecInvalid;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Geburtsdatum
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birthdate ?? DateTime(1990),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
                  );
                  if (picked != null) setState(() => _birthdate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.birthdateLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.cake),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _birthdate != null
                            ? l.birthdateDisplay(
                                '${_birthdate!.day.toString().padLeft(2, '0')}.${_birthdate!.month.toString().padLeft(2, '0')}.${_birthdate!.year}',
                                _ageFromBirthdate() ?? 0,
                              )
                            : l.birthdateSelect,
                        style: TextStyle(
                          color: _birthdate != null ? null : Colors.grey.shade600,
                        ),
                      ),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Geschlecht
              DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: InputDecoration(
                  labelText: l.genderRecLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                items: Gender.values.map((gender) {
                  return DropdownMenuItem(
                    value: gender,
                    child: Text(gender.localizedName(l)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _gender = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              // Aktivitätslevel
              Text(
                l.activitySectionTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<ActivityLevel>(
                initialValue: _activityLevel,
                decoration: InputDecoration(
                  labelText: l.activityRecLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.directions_run),
                ),
                items: ActivityLevel.values.map((level) {
                  return DropdownMenuItem(
                    value: level,
                    child: Text(level.localizedName(l)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _activityLevel = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              // Gewichtsziel
              Text(
                l.goalSectionTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<WeightGoal>(
                initialValue: _weightGoal,
                decoration: InputDecoration(
                  labelText: l.weightGoalRecLabel,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.flag),
                ),
                items: WeightGoal.values.map((goal) {
                  return DropdownMenuItem(
                    value: goal,
                    child: Text(goal.localizedName(l)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _weightGoal = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              // Macro-only mode toggle
              SwitchListTile(
                title: Text(l.macroOnlyMode),
                subtitle: const Text('Track macros without calorie goals'),
                value: _macroOnly,
                onChanged: (value) {
                  setState(() {
                    _macroOnly = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 32),

              // Berechnen Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCalculating ? null : _calculateRecommendation,
                  icon: const Icon(Icons.calculate),
                  label: Text(_isCalculating ? l.calculating : l.calculateButton),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              // Empfehlung anzeigen
              if (_recommendation != null) ...[
                const SizedBox(height: 32),
                _buildRecommendationCard(_recommendation!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(MacroRecommendation rec) {
    final l = AppLocalizations.of(context)!;
    final macroPercentages = rec.macroPercentages;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.recommend, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Text(
                  l.recommendationTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Tracking-Methode Anzeige (hidden for macro-only mode)
            if (!_macroOnly)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.track_changes, color: Colors.purple.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.trackingMethodLabel(rec.method.localizedName(l)),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rec.method.localizedShortDescription(l),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.purple.shade800,
                      ),
                    ),
                  ],
                ),
              ),

            if (!_macroOnly) ...[
              const SizedBox(height: 16),

              // Grundumsatz & Gesamtumsatz
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.bmrLabel),
                        Text(
                          '${rec.bmr.toInt()} kcal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.tdeeLabel),
                        Text(
                          '${rec.tdee.toInt()} kcal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],

            // Zielkalorien (only show if not macro-only mode)
            if (!_macroOnly)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.targetCalories,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${rec.calories.toInt()} kcal',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Makronährstoffe
            Text(
              l.macronutrients,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildMacroRow(
              l.nutrientProtein,
              rec.protein,
              'g',
              macroPercentages['protein']!,
              Icons.egg,
              Colors.red,
            ),
            const SizedBox(height: 8),
            _buildMacroRow(
              l.nutrientFat,
              rec.fat,
              'g',
              macroPercentages['fat']!,
              Icons.water_drop,
              Colors.orange,
            ),
            const SizedBox(height: 8),
            _buildMacroRow(
              l.nutrientCarbs,
              rec.carbs,
              'g',
              macroPercentages['carbs']!,
              Icons.grass,
              Colors.green,
            ),

            const SizedBox(height: 16),

            // Wasserziel
            Row(
              children: [
                const Icon(Icons.water_drop, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  l.waterTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _waterGoalController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.waterGoalFieldLabel,
                helperText: l.waterGoalFieldHint,
                suffixText: 'ml',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null && parsed > 0) {
                  setState(() => _waterGoalMl = parsed);
                }
              },
            ),

            const SizedBox(height: 24),

            // Tracking-Richtlinien
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        l.trackingWhatToTrack,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rec.method.localizedTrackingGuideline(l),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info-Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getGoalExplanation(l),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Speichern-Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveGoal,
                icon: const Icon(Icons.save),
                label: Text(_isSaving ? l.saving : l.saveAsGoal),
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

  Widget _buildMacroRow(
    String label,
    double grams,
    String unit,
    double percentage,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 2),
              LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 100,
          child: Text(
            '${grams.toInt()} $unit (${percentage.toInt()}%)',
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _getGoalExplanation(AppLocalizations l) {
    switch (_weightGoal) {
      case WeightGoal.lose:
        return l.goalExplainLose;
      case WeightGoal.maintain:
        return l.goalExplainMaintain;
      case WeightGoal.gain:
        return l.goalExplainGain;
    }
  }
}

