import 'package:flutter/material.dart';

import '../models/food_entry.dart';
import '../l10n/app_localizations.dart';

/// Shows a checkbox picker letting the user choose which entries of a meal to
/// repeat. All entries are pre-selected (repeating the whole meal is the common
/// case); the user can deselect the ones they don't want. Returns the selected
/// subset (source order preserved), or `null` if the dialog was cancelled.
///
/// Callers should only invoke this when [entries] holds more than one item — a
/// single-item meal repeats directly without a picker (see the call sites in
/// `food_entries_list_screen.dart` and `quick_food_entry_sheet.dart`).
Future<List<FoodEntry>?> showRepeatMealPicker(
  BuildContext context, {
  required String label,
  required List<FoodEntry> entries,
  bool macroOnly = false,
}) {
  return showDialog<List<FoodEntry>>(
    context: context,
    builder: (_) => _RepeatMealPickerDialog(
      label: label,
      entries: entries,
      macroOnly: macroOnly,
    ),
  );
}

class _RepeatMealPickerDialog extends StatefulWidget {
  final String label;
  final List<FoodEntry> entries;
  final bool macroOnly;

  const _RepeatMealPickerDialog({
    required this.label,
    required this.entries,
    required this.macroOnly,
  });

  @override
  State<_RepeatMealPickerDialog> createState() =>
      _RepeatMealPickerDialogState();
}

class _RepeatMealPickerDialogState extends State<_RepeatMealPickerDialog> {
  late final List<bool> _checked =
      List<bool>.filled(widget.entries.length, true);

  int get _selectedCount => _checked.where((c) => c).length;
  bool get _allSelected => _checked.every((c) => c);

  void _toggleAll() {
    final next = !_allSelected;
    setState(() {
      for (var i = 0; i < _checked.length; i++) {
        _checked[i] = next;
      }
    });
  }

  /// Compact amount string mirroring the Recent-tab formatting: raw grams/ml,
  /// localized portion count, or "N × unit" for everything else.
  String _amountLabel(FoodEntry e, AppLocalizations l) {
    if (e.unit == 'g' || e.unit == 'ml') {
      return '${e.amount.toStringAsFixed(0)}${e.unit}';
    }
    final count = e.amount;
    final countStr = count == count.truncateToDouble()
        ? count.toInt().toString()
        : count.toStringAsFixed(1);
    if (e.unit == 'Portion') {
      return '$countStr ${count == 1.0 ? l.portion : l.portions}';
    }
    return '$countStr × ${e.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            l.repeatSelectTitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton(
                  onPressed: _toggleAll,
                  child: Text(_allSelected ? l.deselectAll : l.selectAll),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.entries.length,
                itemBuilder: (_, i) {
                  final e = widget.entries[i];
                  final amount = _amountLabel(e, l);
                  final subtitle = widget.macroOnly
                      ? amount
                      : '$amount · ${e.calories.toStringAsFixed(0)} kcal';
                  return CheckboxListTile(
                    value: _checked[i],
                    onChanged: (v) =>
                        setState(() => _checked[i] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(e.name, style: const TextStyle(fontSize: 14)),
                    subtitle:
                        Text(subtitle, style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(<FoodEntry>[
                    for (var i = 0; i < widget.entries.length; i++)
                      if (_checked[i]) widget.entries[i],
                  ]),
          child: Text(l.repeatSelectedCount(_selectedCount)),
        ),
      ],
    );
  }
}
