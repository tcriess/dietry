import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/food_entry.dart';
import '../utils/number_utils.dart';
import '../utils/unit_utils.dart';

/// Unit stored for an estimate logged without a weight: one unnamed portion.
/// Matches what meal-template entries use, so the edit screen's totals mode
/// renders it the same way.
const String kUnitPortion = 'Portion';

/// Whether the typed nutrition figures are the entry's totals or a per-100
/// table that still has to be scaled by a weight.
enum EstimateBasis { total, per100 }

/// What the quick-estimate sheet collected, already reduced to entry totals.
///
/// Deliberately *not* a [FoodEntry]: the sheet knows nothing about the user id
/// or the day being logged, so the caller assembles the entry.
class QuickEstimate {
  final String name;

  /// Entry amount + unit. Either a weight (`g`/`ml`) or `1 × Portion` when the
  /// user gave totals without a weight.
  final double amount;
  final String unit;

  /// True only for the weightless case — the nutrition is the whole entry's,
  /// with no per-100 basis behind it.
  final bool isMeal;

  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;
  final double? saturatedFat;

  final bool isLiquid;
  final double? amountMl;
  final EstimateLevel estimateLevel;

  /// Grams the totals correspond to; null for the weightless portion case.
  final double? amountG;

  const QuickEstimate({
    required this.name,
    required this.amount,
    required this.unit,
    required this.isMeal,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    this.saturatedFat,
    required this.isLiquid,
    this.amountMl,
    required this.estimateLevel,
    this.amountG,
  });
}

/// Reduces what the user typed into entry totals.
///
/// [grams] is the weight they gave, or null when they gave none. Two shapes
/// come out of this:
///
///  * **weight known** — the entry is `grams × unit`, and in
///    [EstimateBasis.per100] the figures are scaled by `grams / 100`.
///  * **no weight** — only legal for [EstimateBasis.total]: the figures already
///    describe the whole helping and there is no per-100 basis to recover, so
///    the entry is logged as `1 × Portion` with [QuickEstimate.isMeal] set.
///
/// `ml` doubles as the fluid marker — an entry logged in ml counts towards the
/// day's water intake.
QuickEstimate buildQuickEstimate({
  required String name,
  required EstimateBasis basis,
  required double? grams,
  required String unit,
  required double calories,
  required double protein,
  required double fat,
  required double carbs,
  double? fiber,
  double? sugar,
  double? sodium,
  double? saturatedFat,
  required EstimateLevel estimateLevel,
}) {
  final weightless = grams == null || grams <= 0;
  final scale =
      basis == EstimateBasis.per100 ? (weightless ? 0.0 : grams / 100.0) : 1.0;
  double? opt(double? v) => v == null ? null : v * scale;
  final isLiquid = !weightless && unit == kUnitMl;

  return QuickEstimate(
    name: name,
    amount: weightless ? 1 : grams,
    unit: weightless ? kUnitPortion : unit,
    isMeal: weightless,
    calories: calories * scale,
    protein: protein * scale,
    fat: fat * scale,
    carbs: carbs * scale,
    fiber: opt(fiber),
    sugar: opt(sugar),
    sodium: opt(sodium),
    saturatedFat: opt(saturatedFat),
    isLiquid: isLiquid,
    amountMl: isLiquid ? grams : null,
    estimateLevel: estimateLevel,
    amountG: weightless ? null : grams,
  );
}

/// Bottom sheet for logging a rough entry for something that is neither in the
/// food database nor behind a barcode — a restaurant plate, a slice of a
/// colleague's cake. Nutrition is entered either as totals or per 100 g plus a
/// weight; nothing is written to `food_database`.
///
/// Returns null when cancelled. Promoting such an entry to a real food later is
/// the edit screen's job (see `EditFoodEntryScreen`).
Future<QuickEstimate?> showQuickEstimateSheet(
  BuildContext context, {
  String? initialName,
}) {
  return showModalBottomSheet<QuickEstimate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _QuickEstimateSheet(initialName: initialName),
  );
}

class _QuickEstimateSheet extends StatefulWidget {
  final String? initialName;

  const _QuickEstimateSheet({this.initialName});

  @override
  State<_QuickEstimateSheet> createState() => _QuickEstimateSheetState();
}

class _QuickEstimateSheetState extends State<_QuickEstimateSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  final _amountCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();
  final _sugarCtrl = TextEditingController();
  final _sodiumCtrl = TextEditingController();
  final _saturatedFatCtrl = TextEditingController();

  EstimateBasis _basis = EstimateBasis.total;
  String _unit = kUnitGram;

  /// A quick estimate is by definition not weighed, so "Rough" is the honest
  /// default. The user can still dial it up or down.
  EstimateLevel _estimateLevel = EstimateLevel.medium;

  bool _showOptional = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _caloriesCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    _fiberCtrl.dispose();
    _sugarCtrl.dispose();
    _sodiumCtrl.dispose();
    _saturatedFatCtrl.dispose();
    super.dispose();
  }

  /// Weight the entry represents, or null when none was given. Required in
  /// per-100 mode, optional in totals mode.
  double? get _grams {
    final v = tryParseDouble(_amountCtrl.text);
    return (v != null && v > 0) ? v : null;
  }

  /// Factor the typed figures are multiplied by to reach entry totals: the
  /// weight/100 in per-100 mode, 1 in totals mode.
  double get _scale =>
      _basis == EstimateBasis.per100 ? (_grams ?? 0) / 100.0 : 1.0;

  /// A single field scaled to an entry total — drives the live preview.
  double _total(TextEditingController c) =>
      (tryParseDouble(c.text) ?? 0) * _scale;

  bool get _hasAnyValue =>
      (tryParseDouble(_caloriesCtrl.text) ?? 0) > 0 ||
      (tryParseDouble(_proteinCtrl.text) ?? 0) > 0 ||
      (tryParseDouble(_fatCtrl.text) ?? 0) > 0 ||
      (tryParseDouble(_carbsCtrl.text) ?? 0) > 0;

  /// Something has to be worth logging. Normally that means a nutrient — but a
  /// drink logged in ml still counts towards the day's fluid intake, so a
  /// calorie-free 500 ml is a legitimate entry on its own.
  bool get _isWorthLogging =>
      _hasAnyValue || (_unit == kUnitMl && _grams != null);

  void _submit() {
    final l = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (!_isWorthLogging) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.quickEstimateNeedsValue)),
      );
      return;
    }

    Navigator.of(context).pop(buildQuickEstimate(
      name: _nameCtrl.text.trim(),
      basis: _basis,
      grams: _grams,
      unit: _unit,
      calories: tryParseDouble(_caloriesCtrl.text) ?? 0,
      protein: tryParseDouble(_proteinCtrl.text) ?? 0,
      fat: tryParseDouble(_fatCtrl.text) ?? 0,
      carbs: tryParseDouble(_carbsCtrl.text) ?? 0,
      fiber: tryParseDouble(_fiberCtrl.text),
      sugar: tryParseDouble(_sugarCtrl.text),
      sodium: tryParseDouble(_sodiumCtrl.text),
      saturatedFat: tryParseDouble(_saturatedFatCtrl.text),
      estimateLevel: _estimateLevel,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final perHundred = _basis == EstimateBasis.per100;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.quickEstimateTitle,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(l.quickEstimateHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameCtrl,
              autofocus: widget.initialName == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.foodName,
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.enterName : null,
            ),
            const SizedBox(height: 16),

            // Basis: totals as typed, or a per-100 table scaled by the weight.
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<EstimateBasis>(
                segments: [
                  ButtonSegment(
                    value: EstimateBasis.total,
                    label: Text(l.quickEstimateBasisTotal),
                  ),
                  ButtonSegment(
                    value: EstimateBasis.per100,
                    label: Text(l.quickEstimateBasisPer100),
                  ),
                ],
                selected: {_basis},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _basis = s.first),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: InputDecoration(
                      labelText: perHundred
                          ? l.amount
                          : l.quickEstimateWeightOptional,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                    ],
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final empty = v == null || v.trim().isEmpty;
                      if (empty) {
                        // Optional in totals mode; the entry then counts as a
                        // single portion.
                        return perHundred ? l.enterAmount : null;
                      }
                      final amount = tryParseDouble(v);
                      if (amount == null || amount <= 0) return l.invalidAmount;
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: InputDecoration(
                      labelText: l.unit,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: kUnitGram, child: Text('g')),
                      DropdownMenuItem(value: kUnitMl, child: Text('ml')),
                    ],
                    // ml doubles as the fluid marker: an entry logged in ml
                    // counts towards the day's water intake.
                    onChanged: (v) =>
                        setState(() => _unit = v ?? kUnitGram),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _NutrientRow(
              left: _nutrientField(
                controller: _caloriesCtrl,
                label: l.caloriesLabel,
                suffix: 'kcal',
              ),
              right: _nutrientField(
                controller: _proteinCtrl,
                label: l.proteinLabel,
                suffix: 'g',
              ),
            ),
            const SizedBox(height: 12),
            _NutrientRow(
              left: _nutrientField(
                controller: _fatCtrl,
                label: l.fatLabel,
                suffix: 'g',
              ),
              right: _nutrientField(
                controller: _carbsCtrl,
                label: l.carbsLabel,
                suffix: 'g',
              ),
            ),
            const SizedBox(height: 16),

            _buildEstimatePicker(l),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showOptional = !_showOptional),
                icon: Icon(_showOptional
                    ? Icons.expand_less
                    : Icons.expand_more),
                label: Text(l.optionalSection),
              ),
            ),
            if (_showOptional) ...[
              _NutrientRow(
                left: _nutrientField(
                  controller: _saturatedFatCtrl,
                  label: l.nutrientSaturatedFat,
                  suffix: 'g',
                  helper: l.ofWhichFat,
                ),
                right: _nutrientField(
                  controller: _sugarCtrl,
                  label: l.nutrientSugar,
                  suffix: 'g',
                  helper: l.ofWhichCarbs,
                ),
              ),
              const SizedBox(height: 12),
              _NutrientRow(
                left: _nutrientField(
                  controller: _fiberCtrl,
                  label: l.nutrientFiber,
                  suffix: 'g',
                ),
                right: _nutrientField(
                  controller: _sodiumCtrl,
                  label: l.nutrientSalt,
                  suffix: 'g',
                ),
              ),
            ],

            // Only per-100 mode does arithmetic the user cannot see; in totals
            // mode the preview would just echo the fields back.
            if (perHundred && _grams != null) ...[
              const SizedBox(height: 16),
              _TotalsPreview(
                label: l.totalForAmount('${formatAmount(_grams!)}$_unit'),
                calories: _total(_caloriesCtrl),
                protein: _total(_proteinCtrl),
                fat: _total(_fatCtrl),
                carbs: _total(_carbsCtrl),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add),
                label: Text(l.add),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimatePicker(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.estimateLabel,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: EstimateLevel.values.map((lvl) {
            // ExcludeFocus: keep the chip from stealing focus so tapping it
            // doesn't dismiss the keyboard and drop the tap.
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

  Widget _nutrientField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
      ],
      onChanged: (_) => setState(() {}),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _NutrientRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _TotalsPreview extends StatelessWidget {
  final String label;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const _TotalsPreview({
    required this.label,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSecondaryContainer)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Macro('kcal', calories.toStringAsFixed(0)),
                _Macro('P', '${protein.toStringAsFixed(1)}g'),
                _Macro('F', '${fat.toStringAsFixed(1)}g'),
                _Macro('KH', '${carbs.toStringAsFixed(1)}g'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  final String label;
  final String value;

  const _Macro(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: scheme.onSecondaryContainer)),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: scheme.onSecondaryContainer.withValues(alpha: 0.7))),
      ],
    );
  }
}
