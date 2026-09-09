import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/exercise_credit.dart';
import '../l10n/app_localizations.dart';

/// What the user chose in [showExerciseCreditDialog]: [factor] is the level's
/// own value, `null` meaning "no opinion here, inherit from the level above".
/// The dialog returns null when it was dismissed, so `null` result and
/// `factor == null` are different answers.
class ExerciseCreditChoice {
  final double? factor;
  const ExerciseCreditChoice(this.factor);
}

/// Asks how much of a burn should count towards the calorie budget.
///
/// One dialog for all three levels — profile default, single day, single
/// activity — because the question is the same each time and only the escape
/// hatch differs. [inheritLabel] names that escape hatch ("use the default",
/// "follow the day", "count all of it") and choosing it answers with a null
/// factor; [inheritedFactor] is what would then apply, used to pre-fill the
/// field so the dialog opens showing the number actually in force rather than
/// an empty box.
Future<ExerciseCreditChoice?> showExerciseCreditDialog(
  BuildContext context, {
  required String title,
  required double? current,
  required double inheritedFactor,
  required String inheritLabel,
}) {
  return showDialog<ExerciseCreditChoice>(
    context: context,
    builder: (ctx) => _ExerciseCreditDialog(
      title: title,
      current: current,
      inheritedFactor: inheritedFactor,
      inheritLabel: inheritLabel,
    ),
  );
}

class _ExerciseCreditDialog extends StatefulWidget {
  final String title;
  final double? current;
  final double inheritedFactor;
  final String inheritLabel;

  const _ExerciseCreditDialog({
    required this.title,
    required this.current,
    required this.inheritedFactor,
    required this.inheritLabel,
  });

  @override
  State<_ExerciseCreditDialog> createState() => _ExerciseCreditDialogState();
}

class _ExerciseCreditDialogState extends State<_ExerciseCreditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final shown = widget.current ?? widget.inheritedFactor;
    _controller = TextEditingController(
      text: (shown * 100).round().toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context)!;
    final factor = ExerciseCredit.parsePercent(_controller.text);
    if (factor == null) {
      setState(() => _error = l.exerciseCreditInvalid);
      return;
    }
    Navigator.of(context).pop(ExerciseCreditChoice(factor));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l.exerciseCreditFieldLabel,
              helperText: l.exerciseCreditFieldHelper,
              helperMaxLines: 2,
              errorText: _error,
              suffixText: '%',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.exerciseCreditExplainer,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
      actions: [
        // Leftmost, and deliberately not styled as the primary action: falling
        // back to the level above is a normal answer, not an "undo".
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const ExerciseCreditChoice(null)),
          child: Text(widget.inheritLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}

/// Form row for a single activity's credit factor, shaped like the other
/// fields around it (an [InputDecorator] rather than a [ListTile], so the add
/// and edit forms stay visually one column).
///
/// [value] is the activity's own factor and null means "follow the day";
/// [inheritedFactor] is what applies in that case, so the row can show the real
/// number instead of the word "default".
class ExerciseCreditField extends StatelessWidget {
  final double? value;
  final double inheritedFactor;
  final ValueChanged<double?> onChanged;

  const ExerciseCreditField({
    super.key,
    required this.value,
    required this.inheritedFactor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final effective = value ?? inheritedFactor;
    final label = ExerciseCredit.formatPercent(effective);

    return InkWell(
      onTap: () async {
        final choice = await showExerciseCreditDialog(
          context,
          title: l.exerciseCreditActivityTitle,
          current: value,
          inheritedFactor: inheritedFactor,
          inheritLabel: l.exerciseCreditFollowDay(
              ExerciseCredit.formatPercent(inheritedFactor)),
        );
        if (choice != null) onChanged(choice.factor);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.exerciseCreditActivityTitle,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.percent),
        ),
        child: Text(
          value == null
              ? l.exerciseCreditFollowDay(label)
              : l.exerciseCreditActivityOwn(label),
        ),
      ),
    );
  }
}
