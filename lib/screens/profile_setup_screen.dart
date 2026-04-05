import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_body_data.dart';
import '../services/user_profile_service.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../l10n/app_localizations.dart';

/// Screen für statische Profildaten (einmalig)
class ProfileSetupScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final UserProfile? existingProfile;

  const ProfileSetupScreen({
    super.key,
    required this.dbService,
    this.existingProfile,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _heightController;

  DateTime? _selectedBirthdate;
  late Gender _selectedGender;
  late ActivityLevel _selectedActivityLevel;
  late WeightGoal _selectedWeightGoal;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final profile = widget.existingProfile;

    _heightController = TextEditingController(
      text: profile?.height?.toStringAsFixed(0) ?? '',
    );

    _selectedBirthdate = profile?.birthdate;
    _selectedGender = profile?.gender ?? Gender.male;
    _selectedActivityLevel = profile?.activityLevel ?? ActivityLevel.moderate;
    _selectedWeightGoal = profile?.weightGoal ?? WeightGoal.maintain;
  }

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthdate ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
    );

    if (picked != null) {
      setState(() {
        _selectedBirthdate = picked;
      });
    }
  }

  Future<void> _saveProfile() async {
    final l = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedBirthdate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.birthdateRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final profile = UserProfile(
        id: widget.dbService.userId,
        birthdate: _selectedBirthdate,
        height: double.parse(_heightController.text),
        gender: _selectedGender,
        activityLevel: _selectedActivityLevel,
        weightGoal: _selectedWeightGoal,
      );

      final service = UserProfileService(widget.dbService);
      await service.updateProfile(profile);

      // Auto-adjust nutrition goal and wait for completion so profile reloads with updated goal
      await NutritionGoalService.autoAdjustGoal(widget.dbService);

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.profileSaved),
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
    final isEdit = widget.existingProfile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.profileEditTitle : l.profileSetupTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info
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
                        l.profileInfoText,
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Geburtsdatum
            InkWell(
              onTap: _selectBirthdate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '${l.birthdate} *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _selectedBirthdate != null
                      ? '${_selectedBirthdate!.day}.${_selectedBirthdate!.month}.${_selectedBirthdate!.year}'
                      : l.birthdateSelect,
                  style: TextStyle(
                    color: _selectedBirthdate != null ? null : Colors.grey.shade600,
                  ),
                ),
              ),
            ),

            if (_selectedBirthdate != null) ...[
              const SizedBox(height: 8),
              Text(
                l.ageYears(UserProfile(birthdate: _selectedBirthdate).age ?? 0),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Größe
            TextFormField(
              controller: _heightController,
              decoration: InputDecoration(
                labelText: l.heightLabel,
                suffixText: 'cm',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.requiredField;
                }
                final height = double.tryParse(value);
                if (height == null || height < 100 || height > 250) {
                  return l.heightInvalid;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Geschlecht
            DropdownButtonFormField<Gender>(
              value: _selectedGender,
              decoration: InputDecoration(
                labelText: l.genderLabel,
                border: const OutlineInputBorder(),
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
                    _selectedGender = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // Activity Level
            DropdownButtonFormField<ActivityLevel>(
              value: _selectedActivityLevel,
              decoration: InputDecoration(
                labelText: l.activityLevelFieldLabel,
                border: const OutlineInputBorder(),
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
                    _selectedActivityLevel = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // Weight Goal
            DropdownButtonFormField<WeightGoal>(
              value: _selectedWeightGoal,
              decoration: InputDecoration(
                labelText: l.weightGoalFieldLabel,
                border: const OutlineInputBorder(),
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
                onPressed: _isSaving ? null : _saveProfile,
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
