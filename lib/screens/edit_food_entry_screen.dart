import 'package:flutter/material.dart';
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
  final NeonDatabaseService dbService;
  final FoodEntry entry;

  const EditFoodEntryScreen({
    super.key,
    required this.dbService,
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

  late MealType _selectedMealType;
  FoodPortion? _selectedPortion;
  String _customUnit = 'g';
  FoodItem? _foodItem;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.entry.name);
    _amountController = TextEditingController(text: widget.entry.amount.toStringAsFixed(0));
    _caloriesController = TextEditingController(text: widget.entry.calories.toStringAsFixed(0));
    _proteinController = TextEditingController(text: widget.entry.protein.toStringAsFixed(1));
    _fatController = TextEditingController(text: widget.entry.fat.toStringAsFixed(1));
    _carbsController = TextEditingController(text: widget.entry.carbs.toStringAsFixed(1));
    _selectedMealType = widget.entry.mealType;

    _customUnit = widget.entry.unit;

    if (widget.entry.foodId != null) {
      _loadFoodItem(widget.entry.foodId!);
    }
  }

  Future<void> _loadFoodItem(String foodId) async {
    try {
      final service = FoodDatabaseService(widget.dbService);
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
    super.dispose();
  }

  void _recalculate() {
    final rawAmount = double.tryParse(_amountController.text);
    if (rawAmount == null || rawAmount <= 0) return;

    if (_foodItem != null) {
      // FoodItem available: precise calculation from per-100g values.
      final grams = _selectedPortion != null
          ? rawAmount * _selectedPortion!.amountG
          : rawAmount;
      final nutrition = _foodItem!.calculateNutrition(grams);
      setState(() {
        _caloriesController.text = nutrition['calories']!.toStringAsFixed(0);
        _proteinController.text  = nutrition['protein']!.toStringAsFixed(1);
        _fatController.text      = nutrition['fat']!.toStringAsFixed(1);
        _carbsController.text    = nutrition['carbs']!.toStringAsFixed(1);
      });
    } else {
      // No FoodItem (e.g. meal template entry, manual entry): scale
      // proportionally from the original stored values.
      final originalAmount = widget.entry.amount;
      if (originalAmount <= 0) return;
      final factor = rawAmount / originalAmount;
      setState(() {
        _caloriesController.text = (widget.entry.calories * factor).toStringAsFixed(0);
        _proteinController.text  = (widget.entry.protein  * factor).toStringAsFixed(1);
        _fatController.text      = (widget.entry.fat      * factor).toStringAsFixed(1);
        _carbsController.text    = (widget.entry.carbs    * factor).toStringAsFixed(1);
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isSaving = true; });

    try {
      final rawAmount = double.parse(_amountController.text);
      final displayUnit = _selectedPortion?.name ?? _customUnit;

      final updatedEntry = widget.entry.copyWith(
        name: _nameController.text,
        amount: rawAmount,
        unit: displayUnit,
        mealType: _selectedMealType,
        calories: double.parse(_caloriesController.text),
        protein: double.parse(_proteinController.text),
        fat: double.parse(_fatController.text),
        carbs: double.parse(_carbsController.text),
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
      value: currentKey,
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => _recalculate(),
                    validator: (value) {
                      if (value == null || value.isEmpty) return l.requiredField;
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) return l.weightInvalid;
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildUnitSelector()),
              ],
            ),

            const SizedBox(height: 16),

            // Meal Type
            DropdownButtonFormField<MealType>(
              value: _selectedMealType,
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

            // Nährwerte
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
                    validator: (value) =>
                        (value == null || value.isEmpty) ? l.requiredField : null,
                  ),
                ),
              ],
            ),

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
