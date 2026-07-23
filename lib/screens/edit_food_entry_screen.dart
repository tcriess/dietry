import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../utils/number_utils.dart';
import '../models/food_entry.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
import '../services/food_database_service.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/unit_utils.dart';

/// Screen zum Bearbeiten eines Food-Entries.
///
/// Zwei Bearbeitungsmodi (für Food-Einträge, `isMeal == false`):
///
///  • **per-100g-Modus** — wenn die Einheit g/ml ist ODER eine benannte Portion,
///    deren Grammgewicht aus dem zugehörigen Lebensmittel ermittelt werden kann.
///    Die Nährwertfelder enthalten Werte pro 100 g/ml und werden beim Speichern
///    über die tatsächlichen Gramm auf Totals skaliert.
///
///  • **Totals-Modus** — für Mahlzeiten-Einträge (`isMeal == true`) sowie für
///    Portions-Einträge, deren Lebensmittel/Portion nicht aufgelöst werden kann
///    (gelöscht, umbenannt, Gast-Modus). Die gespeicherten Totals werden über
///    das Mengenverhältnis skaliert — kein per-100g-Roundtrip nötig.
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
  late bool _isLiquid;
  late EstimateLevel _estimateLevel;

  FoodItem? _foodItem;
  FoodPortion? _selectedPortion;
  String _customUnit = 'g';

  /// true → nutrition fields hold per-100g values (editable, round-tripped).
  /// false → totals mode: stored totals scaled by the amount ratio.
  bool _per100gMode = false;

  /// true while the food behind a portion-unit entry is being looked up.
  bool _resolvingFood = false;

  /// Grams the entry originally represented — fixed reference for scaling the
  /// micronutrient row when the amount changes. Only set in per-100g mode.
  double? _originalGrams;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameController = TextEditingController(text: e.name);
    _amountController = TextEditingController(text: formatAmount(e.amount));
    _caloriesController = TextEditingController();
    _proteinController = TextEditingController();
    _fatController = TextEditingController();
    _carbsController = TextEditingController();
    _fiberController = TextEditingController();
    _sugarController = TextEditingController();
    _sodiumController = TextEditingController();
    _saturatedFatController = TextEditingController();
    _selectedMealType = e.mealType;
    _isLiquid = e.isLiquid;
    _estimateLevel = e.estimateLevel;
    _customUnit = e.unit;

    final unit = e.unit;
    if (e.isMeal) {
      // Meal entry: totals mode, scaled by portion count.
      _per100gMode = false;
      _applyTotalsFromEntry();
    } else if (unit == 'g' || unit == 'ml' || unit == kUnitGramCooked) {
      // Weight/volume entry: per-100g mode, grams == amount. A cooked-weight
      // entry rides the same path — its stored totals already reflect the
      // raw/dry basis, so scaling by the (cooked) amount round-trips exactly;
      // we just keep the "g (cooked)" label so it stays editable and readable.
      _per100gMode = true;
      _originalGrams = e.amount;
      _applyPer100gFromEntry(e.amount);
      // Load the food (if any) so the unit selector can offer named portions.
      if (e.foodId != null) _resolveFood(e.foodId!);
    } else {
      // Named-portion entry: mode depends on whether the portion resolves.
      if (e.foodId != null) {
        _resolvingFood = true;
        _applyTotalsFromEntry(); // placeholder while the food loads
        _resolveFood(e.foodId!);
      } else {
        // No food reference → cannot resolve grams → totals mode.
        _per100gMode = false;
        _applyTotalsFromEntry();
      }
    }
  }

  /// Fills the nutrition controllers with the entry's stored totals.
  void _applyTotalsFromEntry() {
    final e = widget.entry;
    _caloriesController.text = e.calories.toStringAsFixed(0);
    _proteinController.text = e.protein.toStringAsFixed(1);
    _fatController.text = e.fat.toStringAsFixed(1);
    _carbsController.text = e.carbs.toStringAsFixed(1);
    _fiberController.text = e.fiber?.toStringAsFixed(1) ?? '';
    _sugarController.text = e.sugar?.toStringAsFixed(1) ?? '';
    _sodiumController.text = e.sodium?.toStringAsFixed(1) ?? '';
    _saturatedFatController.text = e.saturatedFat?.toStringAsFixed(1) ?? '';
  }

  /// Fills the nutrition controllers with per-100g values derived from the
  /// entry's stored totals and the [grams] those totals correspond to.
  /// Converts ALL eight nutrients (macros + optional) consistently.
  void _applyPer100gFromEntry(double grams) {
    final e = widget.entry;
    _caloriesController.text = toPer100g(e.calories, grams).toStringAsFixed(0);
    _proteinController.text = toPer100g(e.protein, grams).toStringAsFixed(1);
    _fatController.text = toPer100g(e.fat, grams).toStringAsFixed(1);
    _carbsController.text = toPer100g(e.carbs, grams).toStringAsFixed(1);
    _fiberController.text =
        e.fiber != null ? toPer100g(e.fiber!, grams).toStringAsFixed(1) : '';
    _sugarController.text =
        e.sugar != null ? toPer100g(e.sugar!, grams).toStringAsFixed(1) : '';
    _sodiumController.text =
        e.sodium != null ? toPer100g(e.sodium!, grams).toStringAsFixed(1) : '';
    _saturatedFatController.text = e.saturatedFat != null
        ? toPer100g(e.saturatedFat!, grams).toStringAsFixed(1)
        : '';
  }

  /// Loads the food behind the entry. For a portion-unit entry this also
  /// decides the edit mode: per-100g if the portion resolves, totals otherwise.
  Future<void> _resolveFood(String foodId) async {
    FoodItem? food;
    try {
      if (widget.dbService != null) {
        food = await FoodDatabaseService(widget.dbService!).getFoodById(foodId);
      }
    } catch (_) {
      // Network/lookup failure — fall back to whatever mode applies below.
    }
    if (!mounted) return;

    setState(() {
      _foodItem = food;
      if (!_resolvingFood) {
        // g/ml entry — food is only needed to populate the unit selector.
        return;
      }
      FoodPortion? portion;
      for (final p in food?.portions ?? const <FoodPortion>[]) {
        if (p.name == widget.entry.unit) {
          portion = p;
          break;
        }
      }
      if (portion != null) {
        _selectedPortion = portion;
        _originalGrams = widget.entry.amount * portion.amountG;
        _per100gMode = true;
        _applyPer100gFromEntry(_originalGrams!);
      } else {
        // Food deleted or portion renamed → keep totals, scale by count.
        _per100gMode = false;
        _applyTotalsFromEntry();
      }
      _resolvingFood = false;
    });
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

  /// Grams represented by the current amount + unit. Only valid in per-100g mode.
  double _currentGrams() {
    final amount = tryParseDouble(_amountController.text) ?? 0;
    if (amount <= 0) return 0;
    return _selectedPortion != null
        ? amount * _selectedPortion!.amountG
        : amount; // g or ml
  }

  /// Total nutrition for the current amount — used by the preview card.
  Map<String, double> _computeTotals() {
    final amount = tryParseDouble(_amountController.text) ?? 0;
    if (amount <= 0) {
      return {'calories': 0, 'protein': 0, 'fat': 0, 'carbs': 0};
    }

    if (!_per100gMode) {
      // Totals mode: scale stored totals by the amount ratio.
      if (widget.entry.amount <= 0) return {};
      final scale = amount / widget.entry.amount;
      return {
        'calories': widget.entry.calories * scale,
        'protein': widget.entry.protein * scale,
        'fat': widget.entry.fat * scale,
        'carbs': widget.entry.carbs * scale,
      };
    }

    // Per-100g mode: scale per-100g values by grams.
    final grams = _currentGrams();
    return {
      'calories': scaleToTotal(tryParseDouble(_caloriesController.text) ?? 0, grams),
      'protein': scaleToTotal(tryParseDouble(_proteinController.text) ?? 0, grams),
      'fat': scaleToTotal(tryParseDouble(_fatController.text) ?? 0, grams),
      'carbs': scaleToTotal(tryParseDouble(_carbsController.text) ?? 0, grams),
    };
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final rawAmount = parseDouble(_amountController.text);
      final displayUnit = _selectedPortion?.name ?? _customUnit;

      double totalCalories, totalProtein, totalFat, totalCarbs;
      double? totalFiber, totalSugar, totalSodium, totalSaturatedFat, amountMl;
      double? microRatio; // factor to rescale the food_entry_micros row by

      if (!_per100gMode) {
        // Totals mode (meal entry or unresolved portion): scale stored totals.
        final e = widget.entry;
        final scale = e.amount > 0 ? rawAmount / e.amount : 1.0;
        totalCalories = e.calories * scale;
        totalProtein = e.protein * scale;
        totalFat = e.fat * scale;
        totalCarbs = e.carbs * scale;
        totalFiber = e.fiber != null ? e.fiber! * scale : null;
        totalSugar = e.sugar != null ? e.sugar! * scale : null;
        totalSodium = e.sodium != null ? e.sodium! * scale : null;
        totalSaturatedFat =
            e.saturatedFat != null ? e.saturatedFat! * scale : null;
        if (e.amountMl != null) amountMl = e.amountMl! * scale;
        microRatio = scale;
      } else {
        // Per-100g mode: scale per-100g controller values by grams.
        final grams = _selectedPortion != null
            ? rawAmount * _selectedPortion!.amountG
            : rawAmount; // g or ml

        totalCalories = scaleToTotal(parseDouble(_caloriesController.text), grams);
        totalProtein = scaleToTotal(parseDouble(_proteinController.text), grams);
        totalFat = scaleToTotal(parseDouble(_fatController.text), grams);
        totalCarbs = scaleToTotal(parseDouble(_carbsController.text), grams);
        totalFiber = tryParseDouble(_fiberController.text) != null
            ? scaleToTotal(parseDouble(_fiberController.text), grams)
            : null;
        totalSugar = tryParseDouble(_sugarController.text) != null
            ? scaleToTotal(parseDouble(_sugarController.text), grams)
            : null;
        totalSodium = tryParseDouble(_sodiumController.text) != null
            ? scaleToTotal(parseDouble(_sodiumController.text), grams)
            : null;
        totalSaturatedFat = tryParseDouble(_saturatedFatController.text) != null
            ? scaleToTotal(parseDouble(_saturatedFatController.text), grams)
            : null;

        if (_isLiquid) {
          if (_selectedPortion != null) {
            amountMl = grams; // grams ≈ ml for liquids
          } else if (_customUnit == 'ml') {
            amountMl = rawAmount;
          }
        }

        if (_originalGrams != null && _originalGrams! > 0) {
          microRatio = grams / _originalGrams!;
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
        estimateLevel: _estimateLevel,
        updatedAt: DateTime.now(),
      );

      // Optimistic update — immediately visible in all tabs.
      DataStore.instance.replaceFoodEntry(updatedEntry);

      final saved = await SyncService.instance.updateFoodEntry(updatedEntry);
      if (saved != null) DataStore.instance.replaceFoodEntry(saved);

      // Keep cloud micronutrients in sync with the new amount (best-effort).
      final db = widget.dbService;
      if (db != null &&
          microRatio != null &&
          (microRatio - 1.0).abs() > 1e-9) {
        final jwt = db.jwt;
        if (jwt != null) {
          premiumFeatures.rescaleEntryMicros(
            entryId: widget.entry.id,
            ratio: microRatio,
            authToken: jwt,
            apiUrl: NeonDatabaseService.dataApiUrl,
          );
        }
      }

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
          SnackBar(
              content: Text(lCtx.errorPrefix(e.toString())),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Unit selector — only shown in per-100g mode.
  /// "How sure?" picker — lets the user set/correct this entry's uncertainty.
  Widget _buildEstimatePicker(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.estimateLabel,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: EstimateLevel.values.map((lvl) {
            // ExcludeFocus: keep the chip from stealing focus so tapping it
            // doesn't dismiss the keyboard and drop the tap. See
            // add_food_entry_screen for the full explanation.
            return ExcludeFocus(
              child: ChoiceChip(
                label: Text(lvl.localizedName(l)),
                selected: _estimateLevel == lvl,
                onSelected: (_) => setState(() => _estimateLevel = lvl),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUnitSelector() {
    final l = AppLocalizations.of(context)!;
    final portions = <FoodPortion>[];
    final seenNames = <String>{};
    for (final p in _foodItem?.portions ?? const <FoodPortion>[]) {
      if (seenNames.add(p.name)) portions.add(p);
    }

    final isCooked = _selectedPortion == null && _customUnit == kUnitGramCooked;
    final currentKey = _selectedPortion != null
        ? 'p:${_selectedPortion!.name}'
        : _customUnit;

    final items = <DropdownMenuItem<String>>[
      for (final p in portions)
        DropdownMenuItem(
          value: 'p:${p.name}',
          child: Text('${p.name} (${formatAmount(p.amountG)}g)'),
        ),
      DropdownMenuItem(
          value: 'g', child: Text(unitLabel('g', l, distinguishRaw: isCooked))),
      const DropdownMenuItem(value: 'ml', child: Text('ml')),
      // Only offered when the entry was logged as a cooked weight — the dropdown
      // needs an item matching the current value, and switching a plain g/ml
      // entry to a cooked basis would need a yield factor we don't have here.
      if (isCooked)
        DropdownMenuItem(
            value: kUnitGramCooked, child: Text(unitLabel(kUnitGramCooked, l))),
    ];

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
            _selectedPortion =
                _foodItem?.portions.firstWhere((p) => p.name == name);
            _amountController.text = '1';
          } else {
            // Switching to g/ml — keep grams stable when leaving a portion.
            final wasPortion = _selectedPortion != null;
            _selectedPortion = null;
            _customUnit = value;
            if (wasPortion && _originalGrams != null) {
              _amountController.text = formatAmount(_originalGrams!);
            }
          }
        });
      },
    );
  }

  /// Read-only unit label — shown in totals mode (meal / unresolved portion).
  Widget _buildUnitLabel() {
    final l = AppLocalizations.of(context)!;
    final text = widget.entry.isMeal ? 'Portion' : widget.entry.unit;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 16),
          // Tooltip via Semantics label keeps the field name accessible.
          semanticsLabel: '${l.unit}: $text'),
    );
  }

  /// Card showing total nutrition for the current amount.
  Widget _buildTotalsPreview() {
    final totals = _computeTotals();
    if (totals.isEmpty) return const SizedBox.shrink();

    final amount = tryParseDouble(_amountController.text) ?? 0;
    final amountStr = formatAmount(amount);
    final rawUnit = _per100gMode
        ? (_selectedPortion?.name ?? _customUnit)
        : widget.entry.unit;
    // Cooked weight reads "220 g (gekocht)"; g/ml keep the tight "220g".
    final unitText = rawUnit == kUnitGramCooked
        ? ' ${AppLocalizations.of(context)!.unitGramsCooked}'
        : rawUnit;

    final label = widget.entry.isMeal
        ? 'Nährwerte für $amountStr Portion${amount != 1.0 ? 'en' : ''}:'
        : 'Gesamt für $amountStr$unitText:';

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
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

  /// Editable per-100g nutrition fields.
  Widget _buildPer100gFields(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.nutritionPer100,
            style: Theme.of(context).textTheme.titleMedium),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final sat = tryParseDouble(value);
                  final fat = tryParseDouble(_fatController.text);
                  if (sat != null && fat != null && sat > fat) {
                    return l.satFatExceedsFat;
                  }
                  return null;
                },
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildTotalsPreview(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l.editEntryTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l.foodName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? l.requiredField
                      : null,
            ),
            const SizedBox(height: 16),

            // Amount & unit
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*[.,]?\d*')),
                    ],
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l.requiredField;
                      }
                      final amount = tryParseDouble(value);
                      if (amount == null || amount <= 0) {
                        return l.weightInvalid;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _per100gMode ? _buildUnitSelector() : _buildUnitLabel(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Meal type
            DropdownButtonFormField<MealType>(
              initialValue: _selectedMealType,
              decoration: InputDecoration(
                labelText: l.mealType,
                border: const OutlineInputBorder(),
              ),
              items: MealType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            Text(type.icon,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Text(type.localizedName(l)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedMealType = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // How sure? — nutrition uncertainty (drives the daily band).
            _buildEstimatePicker(l),
            const SizedBox(height: 24),

            // Nutrition section
            if (_resolvingFood)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_per100gMode)
              _buildPer100gFields(l)
            else
              // Totals mode (meal / unresolved portion): read-only preview.
              _buildTotalsPreview(),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_isSaving || _resolvingFood) ? null : _saveChanges,
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

/// Simple widget for displaying a macro in the totals preview.
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
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
