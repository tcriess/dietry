import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/exercise_credit.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import 'edit_on_close.dart';

/// What the user chose in [showExerciseCreditDialog]: [factor] is the level's
/// own value, `null` meaning "no opinion here, inherit from the level above".
///
/// The wrapper exists precisely so that answer is a real value: the dialog
/// itself answers with null only when the field held something unusable, and
/// the caller then leaves the stored value alone. See [EditOnClose].
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
///
/// Applies on close — see [EditOnClose]. There is no Save and no Cancel.
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

  /// The current entry, or null when it cannot be stored. Called on whichever
  /// way out of the dialog the user took.
  ExerciseCreditChoice? _commit() {
    final factor = ExerciseCredit.parsePercent(_controller.text);
    return factor == null ? null : ExerciseCreditChoice(factor);
  }

  /// Live validation, so the entry is marked bad while it is being typed rather
  /// than only once the dialog is on its way out.
  void _validate(String text) {
    final l = AppLocalizations.of(context)!;
    final error = ExerciseCredit.parsePercent(text) == null
        ? l.exerciseCreditInvalid
        : null;
    if (error != _error) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EditOnClose<ExerciseCreditChoice>(
      commit: _commit,
      invalidMessage: l.editDiscardedInvalid,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textInputAction: TextInputAction.done,
              onChanged: _validate,
              onSubmitted: (_) => Navigator.of(context).maybePop(),
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
                  ?.copyWith(color: context.colors.muted),
            ),
          ],
        ),
        actions: [
          // Leftmost, and deliberately not styled as the primary action: falling
          // back to the level above is a normal answer, not an "undo". A direct
          // pop, so it answers with its own value instead of the field's.
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const ExerciseCreditChoice(null)),
            child: Text(widget.inheritLabel),
          ),
          EditDoneButton(enabled: _error == null),
        ],
      ),
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
