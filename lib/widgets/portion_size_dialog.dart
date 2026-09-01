import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/food_portion.dart';
import '../utils/number_utils.dart';
import '../utils/unit_utils.dart';

/// Dropdown value standing for the "define a new portion size" action rather
/// than a unit. Prefixed with a control character so it can never collide with
/// a user-authored portion name.
const String kAddPortionValue = '\u0000add_portion';

/// Why a proposed portion name cannot be used. Null means it is fine.
///
/// Kept as a pure function so the rules are testable without pumping a widget —
/// the same rules apply wherever portions are authored.
enum PortionNameError {
  /// Empty or whitespace only.
  empty,

  /// The food already carries a portion by that name. Duplicate names would
  /// make the unit dropdown ambiguous and break unit → grams resolution, which
  /// looks portion names up by name.
  duplicate,

  /// Collides with a built-in unit token ('g', 'ml', 'g_cooked') or its
  /// localized label. Those already appear in every unit dropdown, so a
  /// same-named portion would put two identically-valued items in it — which
  /// trips DropdownButton's "exactly one item" assertion.
  reserved,
}

/// Validates [name] as a new portion name for a food that already has
/// [existing] portions. Comparison is case-insensitive and trims whitespace,
/// matching how the food-edit dialogs deduplicate.
PortionNameError? validatePortionName(
  String name,
  List<FoodPortion> existing, {
  required List<String> reservedLabels,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return PortionNameError.empty;
  final lower = trimmed.toLowerCase();
  if (existing.any((p) => p.name.trim().toLowerCase() == lower)) {
    return PortionNameError.duplicate;
  }
  const builtIns = [kUnitGram, kUnitMl, kUnitGramCooked];
  if (builtIns.contains(lower) ||
      reservedLabels.any((r) => r.toLowerCase() == lower)) {
    return PortionNameError.reserved;
  }
  return null;
}

/// What the add-portion dialog hands back: the portion itself, and whether the
/// food's per-100 g values should be re-based to it.
typedef NewPortion = ({FoodPortion portion, bool rebaseNutrition});

/// Asks for a named portion size (e.g. "1 bar" = 30 g) and returns it, or null
/// if cancelled. Purely a form — persisting is the caller's job.
///
/// [initialAmount] pre-fills the weight from whatever the user already typed in
/// the surrounding entry form, so naming a portion they just weighed is a
/// single field of typing.
///
/// [caloriesPer100g] enables the "these values are for this amount" correction:
/// naming a portion is the moment the user establishes what one packet weighs,
/// which is also the moment a food carrying per-packet figures in its per-100 g
/// columns can be put right. Pass null to leave the offer out.
Future<NewPortion?> showAddPortionSizeDialog(
  BuildContext context, {
  required List<FoodPortion> existing,
  double? initialAmount,
  bool isLiquid = false,
  double? caloriesPer100g,
}) {
  return showDialog<NewPortion>(
    context: context,
    builder: (_) => _AddPortionSizeDialog(
      existing: existing,
      initialAmount: initialAmount,
      isLiquid: isLiquid,
      caloriesPer100g: caloriesPer100g,
    ),
  );
}

class _AddPortionSizeDialog extends StatefulWidget {
  final List<FoodPortion> existing;
  final double? initialAmount;
  final bool isLiquid;
  final double? caloriesPer100g;

  const _AddPortionSizeDialog({
    required this.existing,
    this.initialAmount,
    required this.isLiquid,
    this.caloriesPer100g,
  });

  @override
  State<_AddPortionSizeDialog> createState() => _AddPortionSizeDialogState();
}

class _AddPortionSizeDialogState extends State<_AddPortionSizeDialog> {
  final _nameCtrl = TextEditingController();
  late final TextEditingController _amountCtrl;
  final _nameFocus = FocusNode();

  /// Only shown once the user has tried to save — an error under a field they
  /// have not reached yet is noise.
  bool _submitted = false;

  /// "The nutrition values are for this amount, not per 100 g." Off by default:
  /// it rewrites the food, and the common case is a food that is already right.
  bool _rebase = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAmount;
    _amountCtrl = TextEditingController(
      text: initial != null && initial > 0 ? formatAmount(initial) : '',
    );
    // The weight is usually pre-filled, so the name is the only thing left to
    // type — start there.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String get _unitSuffix => widget.isLiquid ? kUnitMl : kUnitGram;

  PortionNameError? _nameError(AppLocalizations l) => validatePortionName(
        _nameCtrl.text,
        widget.existing,
        reservedLabels: [
          unitLabel(kUnitGram, l, distinguishRaw: true),
          unitLabel(kUnitGramCooked, l),
        ],
      );

  String? _nameErrorText(AppLocalizations l) {
    if (!_submitted) return null;
    return switch (_nameError(l)) {
      PortionNameError.empty => l.portionNameRequired,
      PortionNameError.duplicate => l.portionNameDuplicate,
      PortionNameError.reserved => l.portionNameReserved,
      null => null,
    };
  }

  double? get _amount {
    final v = tryParseDouble(_amountCtrl.text);
    return (v != null && v > 0) ? v : null;
  }

  /// Whether the "values are for this amount" correction can be offered — it
  /// needs a food with per-100 g values to rewrite.
  bool get _canRebase =>
      widget.caloriesPer100g != null && widget.caloriesPer100g! > 0;

  /// The per-100 g energy the correction would produce, or null while the
  /// amount is not a usable number.
  double? get _rebasedCalories {
    final amount = _amount;
    if (!_canRebase || amount == null) return null;
    return widget.caloriesPer100g! * 100 / amount;
  }

  void _submit(AppLocalizations l) {
    setState(() => _submitted = true);
    if (_nameError(l) != null || _amount == null) return;
    Navigator.of(context).pop((
      portion: FoodPortion(name: _nameCtrl.text.trim(), amountG: _amount!),
      rebaseNutrition: _rebase && _canRebase,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.portionAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.portionNameLabel,
              hintText: l.portionNameHint,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _nameErrorText(l),
            ),
            onChanged: (_) {
              if (_submitted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            textInputAction: TextInputAction.done,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
            ],
            decoration: InputDecoration(
              labelText: l.portionAmountLabel,
              suffixText: _unitSuffix,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _submitted && _amount == null
                  ? l.portionAmountInvalid
                  : null,
            ),
            onChanged: (_) {
              // The rebase preview reads the amount, so it has to follow every
              // keystroke — not just once an error is on screen.
              if (_submitted || _canRebase) setState(() {});
            },
            onSubmitted: (_) => _submit(l),
          ),
          // Naming a portion is the moment the packet's weight is known, so it
          // is also the moment a food whose "per 100 g" values are really the
          // packet's can be put right — in one tap, instead of a trip to the
          // food editor with a calculator.
          if (_canRebase) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _rebase,
              onChanged: (v) => setState(() => _rebase = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.portionRebaseLabel,
                  style: const TextStyle(fontSize: 13)),
              subtitle: _rebasedCalories == null
                  ? null
                  : Text(
                      l.portionRebaseHint(
                        formatAmount(widget.caloriesPer100g!),
                        formatAmount(_rebasedCalories!),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => _submit(l),
          child: Text(l.save),
        ),
      ],
    );
  }
}
