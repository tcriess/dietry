import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../utils/number_utils.dart';

/// Outcome of the calibration dialog. [factor] null means "drop my measurement
/// and go back to the app's generic factor"; the dialog returning null at all
/// means the user cancelled.
class CookedFactorResult {
  final double? factor;
  const CookedFactorResult(this.factor);
}

/// Lets the user measure their own raw→cooked yield for one food.
///
/// The generic factors are averages over a wide published range (pasta 2.0–2.5,
/// rice 2.0–3.0), and most of that spread is *how a given person cooks* rather
/// than measurement error — so one personal measurement is worth more than a
/// better table.
Future<CookedFactorResult?> showCookedFactorDialog(
  BuildContext context, {
  required double defaultFactor,
  double? currentFactor,
}) {
  return showDialog<CookedFactorResult>(
    context: context,
    builder: (ctx) => _CookedFactorDialog(
      defaultFactor: defaultFactor,
      currentFactor: currentFactor,
    ),
  );
}

class _CookedFactorDialog extends StatefulWidget {
  final double defaultFactor;
  final double? currentFactor;

  const _CookedFactorDialog({
    required this.defaultFactor,
    this.currentFactor,
  });

  @override
  State<_CookedFactorDialog> createState() => _CookedFactorDialogState();
}

class _CookedFactorDialogState extends State<_CookedFactorDialog> {
  final _rawCtrl = TextEditingController();
  final _cookedCtrl = TextEditingController();

  @override
  void dispose() {
    _rawCtrl.dispose();
    _cookedCtrl.dispose();
    super.dispose();
  }

  /// Null until both weights are present and plausible. The bounds match the
  /// CHECK constraint on user_food_prefs.cooked_factor, so a typo is caught
  /// here rather than by a 400 from PostgREST.
  double? get _factor {
    final raw = tryParseDouble(_rawCtrl.text);
    final cooked = tryParseDouble(_cookedCtrl.text);
    if (raw == null || cooked == null || raw <= 0 || cooked <= 0) return null;
    final f = cooked / raw;
    if (f < 0.1 || f > 10) return null;
    return f;
  }

  Widget _weightField(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
        ],
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final factor = _factor;

    return AlertDialog(
      title: Text(l.cookedCalibrateTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.cookedCalibrateIntro,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _weightField(_rawCtrl, l.cookedCalibrateRaw),
          const SizedBox(height: 12),
          _weightField(_cookedCtrl, l.cookedCalibrateCooked),
          const SizedBox(height: 12),
          Text(
            factor == null
                ? '—'
                : l.cookedCalibrateResult(
                    factor.toStringAsFixed(2),
                    widget.defaultFactor.toStringAsFixed(2),
                  ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        if (widget.currentFactor != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const CookedFactorResult(null)),
            child: Text(l.cookedCalibrateReset),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: factor == null
              ? null
              : () => Navigator.of(context).pop(CookedFactorResult(factor)),
          child: Text(l.save),
        ),
      ],
    );
  }
}
