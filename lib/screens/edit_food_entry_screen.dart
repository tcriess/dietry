import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import 'package:flutter/services.dart';
import '../models/food_entry.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
import '../services/food_database_service.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';

/// Screen zum Bearbeiten eines Food-Entries
class EditFoodEntryScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final FoodEntry entry;

  const EditFoodEntryScreen({
    super.key,
    this.dbService,
    required this.entry,
  });

  @override
  State<EditFoodEntryScreen> createState() => _EditFoodEntryScreenState();
}

class _EditFoodEntryScreenState extends State<EditFoodEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _caloriesController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;
  late TextEditingController _carbsController;
  late TextEditingController _fiberController;
  late TextEditingController _sugarController;
  late TextEditingController _sodiumController;
  late TextEditingController _saturatedFatController;

  late MealType _selectedMealType;
  FoodPortion? _selectedPortion;
  String _customUnit = 'g';
  FoodItem? _foodItem;
  bool _isSaving = false;
  late bool _isLiquid;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.entry.name);
    _amountController = TextEditingController(text: widget.entry.amount.toStringAsFixed(0));

    // For meal entries (isMeal=true), show totals directly
    // For food entries (isMeal=false), convert totals to per-100g
    final isMealEntry = widget.entry.isMeal;

    if (isMealEntry) {
      // Meal entries: show total nutrition values for the current portion count
      _caloriesController = TextEditingController(text: widget.entry.calories.toStringAsFixed(0));
      _proteinController = TextEditingController(text: widget.entry.protein.toStringAsFixed(1));
      _fatController = TextEditingController(text: widget.entry.fat.toStringAsFixed(1));
      _carbsController = TextEditingController(text: widget.entry.carbs.toStringAsFixed(1));
    } else {
      // Food entries: calculate per-100g values from stored totals
      final per100gNutrition = _calculatePer100g(
        widget.entry.amount,
        widget.entry.unit,
        widget.entry.calories,
        widget.entry.protein,
        widget.entry.fat,
        widget.entry.carbs,
      );

      _caloriesController = TextEditingController(text: per100gNutrition['calories']!.toStringAsFixed(0));
      _proteinController = TextEditingController(text: per100gNutrition['protein']!.toStringAsFixed(1));
      _fatController = TextEditingController(text: per100gNutrition['fat']!.toStringAsFixed(1));
      _carbsController = TextEditingController(text: per100gNutrition['carbs']!.toStringAsFixed(1));
    }

    _selectedMealType = widget.entry.mealType;
    _isLiquid = widget.entry.isLiquid;

    // Optional nutrition fields
    _fiberController = TextEditingController(text: widget.entry.fiber?.toStringAsFixed(1) ?? '');
    _sugarController = TextEditingController(text: widget.entry.sugar?.toStringAsFixed(1) ?? '');
    _sodiumController = TextEditingController(text: widget.entry.sodium?.toStringAsFixed(1) ?? '');
    _saturatedFatController = TextEditingController(text: widget.entry.saturatedFat?.toStringAsFixed(1) ?? '');

    _customUnit = widget.entry.unit;

    if (widget.entry.foodId != null) {
      _loadFoodItem(widget.entry.foodId!);
    }
  }

  /// Calculate per-100g nutrition from stored totals and amount
  Map<String, double> _calculatePer100g(
    double amount,
    String unit,
    double totalCalories,
    double totalProtein,
    double totalFat,
    double totalCarbs,
  ) {
    if (amount <= 0) {
      return {
        'calories': 0,
        'protein': 0,
        'fat': 0,
        'carbs': 0,
      };
    }

    // For g and ml, direct conversion: per_100 = total * 100 / amount
    if (unit == 'g' || unit == 'ml') {
      final factor = 100.0 / amount;
      return {
        'calories': totalCalories * factor,
        'protein': totalProtein * factor,
        'fat': totalFat * factor,
        'carbs': totalCarbs * factor,
      };
    }

    // For portion units (e.g., "1 Scheibe"), we'd need the foodItem to look up grams.
    // For now, return totals as fallback (will be corrected when _foodItem loads).
    return {
      'calories': totalCalories,
      'protein': totalProtein,
      'fat': totalFat,
      'carbs': totalCarbs,
    };
  }

  Future<void> _loadFoodItem(String foodId) async {
    try {
      // In guest mode, dbService is null, so skip loading food item details
      if (widget.dbService == null) {
        return;
      }

      final service = FoodDatabaseService(widget.dbService!);
      final food = await service.getFoodById(foodId);
      if (food != null && mounted) {
        setState(() {
          _foodItem = food;
          // Gespeicherte Einheit auf Portion matchen
          final storedUnit = widget.entry.unit;
          _selectedPortion = food.portions
              .where((p) => p.name == storedUnit)
              .firstOrNull;

          if (_selectedPortion != null) {
            // Portion was found: recalculate per-100g using grams
            // amount = portion count, _selectedPortion.amountG = grams per portion
            final totalGrams = widget.entry.amount * _selectedPortion!.amountG;
            final factor = 100.0 / totalGrams;
            _caloriesController.text = (widget.entry.calories * factor).toStringAsFixed(0);
            _proteinController.text = (widget.entry.protein * factor).toStringAsFixed(1);
            _fatController.text = (widget.entry.fat * factor).toStringAsFixed(1);
            _carbsController.text = (widget.entry.carbs * factor).toStringAsFixed(1);

            // amount is stored as portion count — display directly
            final count = widget.entry.amount;
            _amountController.text = count % 1 == 0
                ? count.toStringAsFixed(0)
                : count.toStringAsFixed(1);
          }
          // _customUnit stays as widget.entry.unit (set in initState)
        });
      }
    } catch (_) {
      // Ohne FoodItem: Textfeld als Fallback
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _saturatedFatController.dispose();
    super.dispose();
  }

  void _recalculate() {
    // When editing, we show per-100g values, not totals.
    // The per-100g values are the "recipe" — they don't change when amount changes.
    // So _recalculate doesn't actually need to do anything here.
    // Amount changes don't affect the displayed per-100g nutrition.
  }

  /// Compute total nutrition for the current amount and per-100g values.
  /// For food entries: scales per-100g values by grams.
  /// For meal entries: scales stored totals by portion ratio.
  Map<String, double> _computeTotals() {
    final amount = tryParseDouble(_amountController.text) ?? 0;
    if (amount <= 0) {
      return {
        'calories': 0,
        'protein': 0,
        'fat': 0,
        'carbs': 0,
      };
    }

    if (widget.entry.isMeal) {
      // Meal entries: scale stored totals by portion ratio
      if (widget.entry.amount <= 0) return {};
      final scale = amount / widget.entry.amount;
      return {
        'calories': widget.entry.calories * scale,
        'protein':  widget.entry.protein  * scale,
        'fat':      widget.entry.fat      * scale,
        'carbs':    widget.entry.carbs    * scale,
      };
    }

    // Food entries: scale per-100g values by grams
    final grams = _selectedPortion != null
        ? amount * _selectedPortion!.amountG
        : amount;  // g or ml
    final factor = grams / 100.0;

    return {
      'calories': (tryParseDouble(_caloriesController.text) ?? 0) * factor,
      'protein':  (tryParseDouble(_proteinController.text)  ?? 0) * factor,
      'fat':      (tryParseDouble(_fatController.text)      ?? 0) * factor,
      'carbs':    (tryParseDouble(_carbsController.text)    ?? 0) * factor,
    };
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isSaving = true; });

    try {
      final rawAmount = parseDouble(_amountController.text);
      final displayUnit = _selectedPortion?.name ?? _customUnit;
      final isMealEntry = widget.entry.isMeal;

      double totalCalories;
      double totalProtein;
      double totalFat;
      double totalCarbs;
      double? totalFiber;
      double? totalSugar;
      double? totalSodium;
      double? totalSaturatedFat;
      double? amountMl;

      if (isMealEntry) {
        // For meal entries: scale the original stored totals by the new portion count
        // The fields are read-only, so we read directly from entry, not controllers
        final scaleFactor = rawAmount / widget.entry.amount;
        totalCalories = widget.entry.calories * scaleFactor;
        totalProtein = widget.entry.protein * scaleFactor;
        totalFat = widget.entry.fat * scaleFactor;
        totalCarbs = widget.entry.carbs * scaleFactor;
        totalFiber = widget.entry.fiber != null ? widget.entry.fiber! * scaleFactor : null;
        totalSugar = widget.entry.sugar != null ? widget.entry.sugar! * scaleFactor : null;
        totalSodium = widget.entry.sodium != null ? widget.entry.sodium! * scaleFactor : null;
        totalSaturatedFat = widget.entry.saturatedFat != null ? widget.entry.saturatedFat! * scaleFactor : null;

        // Scale liquid ml contribution proportionally
        if (widget.entry.amountMl != null) {
          amountMl = widget.entry.amountMl! * scaleFactor;
        }
      } else {
        // For food entries: convert per-100g values back to totals
        final per100gCalories = parseDouble(_caloriesController.text);
        final per100gProtein = parseDouble(_proteinController.text);
        final per100gFat = parseDouble(_fatController.text);
        final per100gCarbs = parseDouble(_carbsController.text);

        // Calculate grams for the current unit/amount
        final grams = _selectedPortion != null
            ? rawAmount * _selectedPortion!.amountG
            : (displayUnit == 'g' || displayUnit == 'ml' ? rawAmount : rawAmount);

        // Convert back to totals
        totalCalories = per100gCalories * grams / 100.0;
        totalProtein = per100gProtein * grams / 100.0;
        totalFat = per100gFat * grams / 100.0;
        totalCarbs = per100gCarbs * grams / 100.0;

        // Optional fields: convert per-100g to totals
        totalFiber = tryParseDouble(_fiberController.text) != null
            ? parseDouble(_fiberController.text) * grams / 100.0
            : null;
        totalSugar = tryParseDouble(_sugarController.text) != null
            ? parseDouble(_sugarController.text) * grams / 100.0
            : null;
        totalSodium = tryParseDouble(_sodiumController.text) != null
            ? parseDouble(_sodiumController.text) * grams / 100.0
            : null;
        totalSaturatedFat = tryParseDouble(_saturatedFatController.text) != null
            ? parseDouble(_saturatedFatController.text) * grams / 100.0
            : null;

        // Calculate amountMl for liquid foods
        if (_isLiquid) {
          if (_selectedPortion != null) {
            // Portion: amount * portion.amountG (treating G as ml for liquid foods)
            amountMl = rawAmount * _selectedPortion!.amountG;
          } else if (_customUnit == 'ml') {
            // Direct ml entry
            amountMl = rawAmount;
          }
        }
      }

      final updatedEntry = widget.entry.copyWith(
        name: _nameController.text,
        amount: rawAmount,
        unit: displayUnit,
        mealType: _selectedMealType,
        calories: totalCalories,
        protein: totalProtein,
        fat: totalFat,
        carbs: totalCarbs,
        fiber: totalFiber,
        sugar: totalSugar,
        sodium: totalSodium,
        saturatedFat: totalSaturatedFat,
        isLiquid: _isLiquid,
        amountMl: amountMl,
        isMeal: widget.entry.isMeal,
        updatedAt: DateTime.now(),
      );

      // Optimistic update — immediately visible in all tabs.
      DataStore.instance.replaceFoodEntry(updatedEntry);

      final saved = await SyncService.instance.updateFoodEntry(updatedEntry);
      if (saved != null) DataStore.instance.replaceFoodEntry(saved);

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.entryUpdated),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lCtx.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  Widget _buildUnitSelector() {
    final food = _foodItem;
    final portions = food?.portions ?? [];

    final currentKey = _selectedPortion != null
        ? 'p:${_selectedPortion!.name}'
        : _customUnit;

    final items = <DropdownMenuItem<String>>[];
    for (final p in portions) {
      items.add(DropdownMenuItem(
        value: 'p:${p.name}',
        child: Text(
            '${p.name} (${p.amountG % 1 == 0 ? p.amountG.toInt() : p.amountG}g)'),
      ));
    }
    items.add(const DropdownMenuItem(value: 'g', child: Text('g')));
    items.add(const DropdownMenuItem(value: 'ml', child: Text('ml')));

    // Wenn Portion nicht gefunden und Unit kein g/ml: als zusätzliche Option zeigen
    if (_selectedPortion == null && _customUnit != 'g' && _customUnit != 'ml') {
      items.insert(0, DropdownMenuItem(
        value: _customUnit,
        child: Text(_customUnit),
      ));
    }

    final l = AppLocalizations.of(context)!;
    return DropdownButtonFormField<String>(
      initialValue: currentKey,
      decoration: InputDecoration(
        labelText: l.unit,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          if (value.startsWith('p:')) {
            final name = value.substring(2);
            _selectedPortion = food?.portions.firstWhere((p) => p.name == name);
            _amountController.text = '1';
          } else {
            _selectedPortion = null;
            _customUnit = value;
          }
          _recalculate();
        });
      },
    );
  }

  /// Build a card showing total nutrition for the current amount.
  /// Shown for both food entries and meal entries (as read-only preview for meals).
  Widget _buildTotalsPreview() {
    final totals = _computeTotals();
    if (totals.isEmpty) return const SizedBox.shrink();

    final amount = tryParseDouble(_amountController.text) ?? 0;
    final amountStr = amount == amount.truncateToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);

    // Label differs for meals vs foods
    final label = widget.entry.isMeal
        ? 'Nährwerte für $amountStr Portion${amount != 1.0 ? 'en' : ''}:'
        : 'Gesamt für $amountStr${_selectedPortion?.name ?? _customUnit}:';

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _PreviewMacro('kcal', totals['calories']!.toStringAsFixed(0)),
                _PreviewMacro('P', '${totals['protein']!.toStringAsFixed(1)}g'),
                _PreviewMacro('F', '${totals['fat']!.toStringAsFixed(1)}g'),
                _PreviewMacro('KH', '${totals['carbs']!.toStringAsFixed(1)}g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.editEntryTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l.foodName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l.requiredField;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Menge & Einheit
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: l.amount,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                    ],
                    onChanged: (_) {
                      _recalculate();
                      setState(() {});  // Update preview
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) return l.requiredField;
                      final amount = tryParseDouble(value);
                      if (amount == null || amount <= 0) return l.weightInvalid;
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // For meal entries, show read-only unit label; for foods, show selector
                Expanded(
                  child: widget.entry.isMeal
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Portion', style: TextStyle(fontSize: 16)),
                        )
                      : _buildUnitSelector(),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Meal Type
            DropdownButtonFormField<MealType>(
              initialValue: _selectedMealType,
              decoration: InputDecoration(
                labelText: l.mealType,
                border: const OutlineInputBorder(),
              ),
              items: MealType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Text(type.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(type.localizedName(l)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() { _selectedMealType = value; });
              },
            ),

            const SizedBox(height: 24),

            // Nährwerte section
            if (widget.entry.isMeal) ...[
              // Meal entries: show read-only preview only
              _buildTotalsPreview(),
            ] else ...[
              // Food entries: show editable per-100g fields + preview
              Text(
                l.nutritionPer100,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      decoration: InputDecoration(
                        labelText: l.caloriesLabel,
                        suffixText: 'kcal',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),  // Update preview
                      validator: (value) =>
                          (value == null || value.isEmpty) ? l.requiredField : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _proteinController,
                      decoration: InputDecoration(
                        labelText: l.proteinLabel,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),  // Update preview
                      validator: (value) =>
                          (value == null || value.isEmpty) ? l.requiredField : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fatController,
                      decoration: InputDecoration(
                        labelText: l.fatLabel,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),  // Update preview
                      validator: (value) =>
                          (value == null || value.isEmpty) ? l.requiredField : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsController,
                      decoration: InputDecoration(
                        labelText: l.carbsLabel,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),  // Update preview
                      validator: (value) =>
                          (value == null || value.isEmpty) ? l.requiredField : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              Text('Optional', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _saturatedFatController,
                      decoration: InputDecoration(
                        labelText: l.nutrientSaturatedFat,
                        helperText: l.ofWhichFat,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sugarController,
                      decoration: InputDecoration(
                        labelText: l.nutrientSugar,
                        helperText: l.ofWhichCarbs,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fiberController,
                      decoration: InputDecoration(
                        labelText: l.nutrientFiber,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sodiumController,
                      decoration: InputDecoration(
                        labelText: l.nutrientSalt,
                        suffixText: 'g',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              _buildTotalsPreview(),
            ],

            const SizedBox(height: 24),

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

/// Simple widget for displaying a macro in the totals preview
class _PreviewMacro extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewMacro(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
