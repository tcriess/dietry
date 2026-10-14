import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/data_store.dart';
import '../theme/app_colors.dart';

/// Closes or reopens [date] and confirms it with a snackbar.
Future<void> toggleDayClosed(BuildContext context, DateTime date,
    {required bool closed}) async {
  final l = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await DataStore.instance.setDayClosed(date, closed);
    messenger.showSnackBar(SnackBar(
      content: Text(closed ? l.dayClosedSnack : l.dayReopenedSnack),
      duration: const Duration(seconds: 2),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.errorPrefix('$e'))));
  }
}

/// "Day closed" notice with a Reopen button. Renders nothing while the
/// selected day is open.
class ClosedDayBanner extends StatelessWidget {
  final DateTime selectedDay;
  final EdgeInsetsGeometry margin;

  const ClosedDayBanner({
    super.key,
    required this.selectedDay,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (!DataStore.instance.isDayClosed) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: margin,
      color: context.colors.neutralContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: context.colors.onNeutralContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.dayClosedBanner,
                style: TextStyle(color: context.colors.onNeutralContainer),
              ),
            ),
            TextButton(
              onPressed: () =>
                  toggleDayClosed(context, selectedDay, closed: false),
              child: Text(l.reopenDay),
            ),
          ],
        ),
      ),
    );
  }
}
