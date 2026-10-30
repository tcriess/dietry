import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/food_entry.dart' show MealType;
import '../l10n/app_localizations.dart';
import '../services/data_store.dart';
import '../theme/app_colors.dart';

/// Whether the user chose to duplicate an entry (leaving the original in
/// place), to relocate it, or to delete it outright.
enum MoveCopyAction { copy, move, delete }

/// The target the user picked in [showMoveCopySheet]: a [day] and a [meal],
/// plus which [action] to perform. For [MoveCopyAction.delete] the day and the
/// meal carry no meaning.
class MoveCopyResult {
  final DateTime day;
  final MealType meal;
  final MoveCopyAction action;

  const MoveCopyResult({
    required this.day,
    required this.meal,
    required this.action,
  });
}

/// Bottom sheet for relocating or duplicating a log entry. Lets the user pick a
/// target **day** (with quick Yesterday / Today / Tomorrow chips plus a date
/// picker) and a target **meal** (breakfast / lunch / dinner / snack), then tap
/// Copy or Move. The day starts on **today**, which is where an entry pulled up
/// from an older day almost always wants to go. The sheet also carries the
/// delete action, which is the only way to remove an entry that is not on
/// today's log. Move and Copy are disabled while the target day is closed.
/// With [sourceClosed] the entry's own day is closed: only Copy is offered.
/// Returns the chosen [MoveCopyResult], or null if dismissed.
///
/// Shared by the food log and the activity log so both behave identically.
Future<MoveCopyResult?> showMoveCopySheet(
  BuildContext context, {
  required String title,
  required MealType initialMeal,
  bool sourceClosed = false,
}) {
  return showModalBottomSheet<MoveCopyResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MoveCopySheet(
      title: title,
      initialMeal: initialMeal,
      sourceClosed: sourceClosed,
    ),
  );
}

class _MoveCopySheet extends StatefulWidget {
  final String title;
  final MealType initialMeal;
  final bool sourceClosed;

  const _MoveCopySheet({
    required this.title,
    required this.initialMeal,
    required this.sourceClosed,
  });

  @override
  State<_MoveCopySheet> createState() => _MoveCopySheetState();
}

class _MoveCopySheetState extends State<_MoveCopySheet> {
  late DateTime _day;
  late MealType _meal;

  /// Whether [_day] is closed; null while the lookup is running.
  bool? _targetClosed;

  @override
  void initState() {
    super.initState();
    _meal = widget.initialMeal;
    _setDay(DateUtils.dateOnly(DateTime.now()));
  }

  void _setDay(DateTime day) {
    setState(() {
      _day = day;
      _targetClosed = null;
    });
    DataStore.instance.isClosedOn(day).then((closed) {
      // Drop answers for a day the user has already moved away from.
      if (mounted && DateUtils.isSameDay(_day, day)) {
        setState(() => _targetClosed = closed);
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) _setDay(DateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final today = DateUtils.dateOnly(DateTime.now());
    final quickDays = <(String, DateTime)>[
      (l.yesterday, today.subtract(const Duration(days: 1))),
      (l.today, today),
      (l.tomorrow, today.add(const Duration(days: 1))),
    ];
    final dateLabel =
        DateFormat.yMMMMEEEEd(Localizations.localeOf(context).toString())
            .format(_day);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sourceClosed ? l.copy : l.moveOrCopy,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )),
            const SizedBox(height: 2),
            Text(widget.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),

            // ── Day ──────────────────────────────────────────────────────
            Text(l.daySectionLabel,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (label, day) in quickDays)
                  ChoiceChip(
                    label: Text(label),
                    selected: DateUtils.isSameDay(_day, day),
                    onSelected: (_) => _setDay(day),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  label: Text(l.pickDate),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.muted,
                    )),
            if (_targetClosed == true) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 16, color: context.colors.danger.base),
                  const SizedBox(width: 6),
                  Text(l.moveTargetDayClosed,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.colors.danger.base,
                          )),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // ── Meal ─────────────────────────────────────────────────────
            Text(l.mealSectionLabel,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final meal in MealType.values)
                  ChoiceChip(
                    label: Text('${meal.icon} ${meal.localizedName(l)}'),
                    selected: _meal == meal,
                    onSelected: (_) => setState(() => _meal = meal),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Actions ──────────────────────────────────────────────────
            Row(
              children: [
                if (!widget.sourceClosed) ...[
                  IconButton.outlined(
                    icon: const Icon(Icons.delete_outline),
                    style: IconButton.styleFrom(
                        foregroundColor: context.colors.danger.base),
                    tooltip: l.delete,
                    onPressed: () => Navigator.of(context).pop(
                      MoveCopyResult(
                          day: _day,
                          meal: _meal,
                          action: MoveCopyAction.delete),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: Text(l.move),
                      onPressed: _targetClosed != false
                          ? null
                          : () => Navigator.of(context).pop(
                                MoveCopyResult(
                                    day: _day,
                                    meal: _meal,
                                    action: MoveCopyAction.move),
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.copy_all_outlined),
                    label: Text(l.copy),
                    onPressed: _targetClosed != false
                        ? null
                        : () => Navigator.of(context).pop(
                              MoveCopyResult(
                                  day: _day,
                                  meal: _meal,
                                  action: MoveCopyAction.copy),
                            ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
