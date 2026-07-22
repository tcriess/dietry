import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Points out that the nutrition values on hand are declared for the food as
/// sold — raw or dry — and offers to switch the entry to a cooked weight.
///
/// Shown for dry goods (pasta, rice, legumes) only, where the yield factor is
/// 2–3× and getting it wrong is the single largest error in a logged day. It
/// disappears as soon as the user touches the unit at all, so answering it once
/// — either way — makes it go away.
class CookedWeightNudge extends StatelessWidget {
  final VoidCallback onSwitchToCooked;

  const CookedWeightNudge({super.key, required this.onSwitchToCooked});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.scale_outlined, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.cookedNudgeText,
              style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: onSwitchToCooked,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l.cookedNudgeAction, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
