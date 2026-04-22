import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/nutrition_calculator.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../services/user_profile_service.dart';
import '../services/user_body_measurements_service.dart';
import '../services/local_data_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';

/// Screen zur Eingabe von Körperdaten und Berechnung von Nutrition Goal Empfehlungen
class GoalRecommendationScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;

  const GoalRecommendationScreen({
    super.key,
    this.dbService,
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
  final _scrollController = ScrollController();
  bool _isCalculating = false;
  bool _isSaving = false;
  bool _isLoadingProfile = true;
  bool _macroOnly = false;
  TrackingMethod _trackingMethod = TrackingMethod.tdeeHybrid;
  UserBodyData? _currentBodyData;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      UserProfile? profile;
      UserBodyMeasurement? measurement;

      if (widget.dbService != null) {
        // Remote mode: load from server
        final profileService = UserProfileService(widget.dbService!);
        final measurementService = UserBodyMeasurementsService(widget.dbService!);

        final results = await Future.wait([
          profileService.getCurrentProfile(),
          measurementService.getCurrentMeasurement(),
        ]);

        profile = results[0] as UserProfile?;
        measurement = results[1] as UserBodyMeasurement?;
      } else {
        // Guest mode: load from local database
        profile = await LocalDataService.instance.getUserProfile();
        measurement = await LocalDataService.instance.getCurrentMeasurement();
      }

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
    _scrollController.dispose();
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
    if (!_formKey.currentState!.validate()) return;
    if (_birthdate == null) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.birthdateSelectSnackbar), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCalculating = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final bodyData = UserBodyData(
        weight: parseDouble(_weightController.text),
        height: parseDouble(_heightController.text),
        gender: _gender,
        age: _ageFromBirthdate()!,
        activityLevel: _activityLevel,
        weightGoal: _weightGoal,
      );

      final method = _macroOnly ? TrackingMethod.tdeeComplete : _trackingMethod;
      final recommendation = NutritionCalculator.calculateMacros(bodyData, method: method);
      final autoWater = NutritionCalculator.calculateWaterGoal(bodyData.weight);

      setState(() {
        _isCalculating = false;
        _recommendation = recommendation;
        _currentBodyData = bodyData;
        _waterGoalMl = autoWater;
        _waterGoalController.text = autoWater.toString();
      });

      appLogger.i('✅ Empfehlung berechnet: ${recommendation.calories.toInt()} kcal (${method.displayName})');

      // Scroll down so the recommendation card is visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isCalculating = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler bei Berechnung: $e'), backgroundColor: Colors.red),
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
      appLogger.d('🔧 Speichermodus wird bestimmt (Remote vs. Guest)...');

      if (widget.dbService != null) {
        // Remote mode: save to server
        appLogger.d('   → REMOTE MODE: Speichere auf Server');
        final goalService = NutritionGoalService(widget.dbService!);
        appLogger.d('   ✅ NutritionGoalService bereit');

        appLogger.d('');
        appLogger.d('💾 SPEICHERE Goal in Server-Datenbank...');
        await goalService.createOrUpdateGoal(goal);
        appLogger.d('   ✅✅✅ GOAL ERFOLGREICH AUF SERVER GESPEICHERT! ✅✅✅');

        // Save profile + measurement alongside goal in remote mode
        if (_birthdate != null) {
          try {
            final profileService = UserProfileService(widget.dbService!);
            final measurementService = UserBodyMeasurementsService(widget.dbService!);
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
      } else {
        // Guest mode: save to local database
        appLogger.d('   → GUEST MODE: Speichere lokal');

        appLogger.d('');
        appLogger.d('💾 SPEICHERE Goal in lokaler Datenbank...');
        await LocalDataService.instance.upsertGoal(goal);
        appLogger.d('   ✅✅✅ GOAL ERFOLGREICH LOKAL GESPEICHERT! ✅✅✅');

        // Save profile + measurement in guest mode
        if (_birthdate != null) {
          try {
            final profile = UserProfile(
              birthdate: _birthdate,
              height: _currentBodyData!.height,
              gender: _currentBodyData!.gender,
              activityLevel: _currentBodyData!.activityLevel,
              weightGoal: _currentBodyData!.weightGoal,
            );
            await LocalDataService.instance.saveUserProfile(profile);
            appLogger.d('   ✅ Profil lokal gespeichert');

            final measurement = UserBodyMeasurement(
              weight: _currentBodyData!.weight,
              measuredAt: DateTime.now(),
            );
            await LocalDataService.instance.saveMeasurement(measurement);
            appLogger.d('   ✅ Körpermessungen lokal gespeichert');
          } catch (e) {
            appLogger.e('⚠️  Fehler beim Speichern von Profil/Messungen (nicht kritisch): $e');
          }
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
        Navigator.of(context).pop();
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
          : Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
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
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+[.,]?\d{0,1}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.weightRequired;
                  }
                  final weight = tryParseDouble(value);
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

              // Tracking method selector (hidden in macro-only mode)
              if (!_macroOnly) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<TrackingMethod>(
                  initialValue: _trackingMethod,
                  decoration: InputDecoration(
                    labelText: l.trackingMethodRecLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.track_changes),
                  ),
                  items: TrackingMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(method.localizedName(l)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _trackingMethod = value);
                  },
                ),
              ],

              // Empfehlung anzeigen
              if (_recommendation != null) ...[
                const SizedBox(height: 32),
                _buildRecommendationCard(_recommendation!),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
          ),
          _buildStickyBar(l),
        ],
      ),
    );
  }

  Widget _buildStickyBar(AppLocalizations l) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _recommendation == null
            ? SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isCalculating ? null : _calculateRecommendation,
                  icon: _isCalculating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.calculate),
                  label: Text(_isCalculating ? l.calculating : l.calculateButton),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isCalculating ? null : _calculateRecommendation,
                      icon: const Icon(Icons.refresh),
                      label: Text(l.recalculateButton),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveGoal,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? l.saving : l.saveAsGoal),
                      style: FilledButton.styleFrom(
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

