import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/food_entry.dart' show MealType;
import '../l10n/app_localizations.dart';

/// Whether the user chose to duplicate an entry (leaving the original in place)
/// or to relocate it.
enum MoveCopyAction { copy, move }

/// The target the user picked in [showMoveCopySheet]: a [day] and a [meal],
/// plus which [action] to perform.
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
/// Copy or Move. Returns the chosen [MoveCopyResult], or null if dismissed.
///
/// Shared by the food log and the activity log so both behave identically.
Future<MoveCopyResult?> showMoveCopySheet(
  BuildContext context, {
  required String title,
  required DateTime initialDay,
  required MealType initialMeal,
}) {
  return showModalBottomSheet<MoveCopyResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MoveCopySheet(
      title: title,
      initialDay: initialDay,
      initialMeal: initialMeal,
    ),
  );
}

class _MoveCopySheet extends StatefulWidget {
  final String title;
  final DateTime initialDay;
  final MealType initialMeal;

  const _MoveCopySheet({
    required this.title,
    required this.initialDay,
    required this.initialMeal,
  });

  @override
  State<_MoveCopySheet> createState() => _MoveCopySheetState();
}

class _MoveCopySheetState extends State<_MoveCopySheet> {
  late DateTime _day;
  late MealType _meal;

  @override
  void initState() {
    super.initState();
    _day = DateUtils.dateOnly(widget.initialDay);
    _meal = widget.initialMeal;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _day = DateUtils.dateOnly(picked));
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
            Text(l.moveOrCopy,
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
                    onSelected: (_) => setState(() => _day = day),
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
                      color: Colors.grey.shade600,
                    )),
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
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_all_outlined),
                    label: Text(l.copy),
                    onPressed: () => Navigator.of(context).pop(
                      MoveCopyResult(
                          day: _day, meal: _meal, action: MoveCopyAction.copy),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: Text(l.move),
                    onPressed: () => Navigator.of(context).pop(
                      MoveCopyResult(
                          day: _day, meal: _meal, action: MoveCopyAction.move),
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
