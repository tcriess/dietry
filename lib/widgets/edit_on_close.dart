import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Dietry's rule for changing something that already exists: **no Save button,
/// and no Cancel**. What is in the editor applies when the editor closes — by
/// the Done button, by the system back gesture, or by tapping outside it.
///
/// Creating something new is the deliberate exception and keeps its explicit
/// action ("Add"): there is nothing to apply until a new record is complete, so
/// a half-filled form must not write anything.
///
/// Why a shared widget rather than a convention each dialog reimplements: the
/// three ways out of a dialog are three different code paths in Flutter, and a
/// dialog that commits on Done but silently drops the edit on a back gesture is
/// worse than one with a Save button. Routing all three through one callback is
/// the only way they stay in step.
///
/// Usage — wrap the [AlertDialog], and hand back the value to apply:
///
/// ```dart
/// showDialog<Choice>(
///   context: context,
///   builder: (ctx) => EditOnClose<Choice>(
///     commit: () => _parse(),                  // null = nothing to apply
///     invalidMessage: l.editDiscardedInvalid,
///     child: AlertDialog(
///       …,
///       actions: const [EditDoneButton()],
///     ),
///   ),
/// );
/// ```
class EditOnClose<T> extends StatelessWidget {
  /// Called exactly once, on whichever close path the user took. Returns the
  /// value to hand back to the caller, or **null** when what is in the editor
  /// cannot be stored — the previous value then stands and [invalidMessage] is
  /// shown.
  ///
  /// Note that null means "nothing to apply", not "the user chose nothing": a
  /// dialog whose empty answer is meaningful (say, "inherit the default")
  /// should wrap it in a type of its own so that answer is a real value.
  final T? Function() commit;

  /// Shown when [commit] returns null. Omit where an unusable entry is
  /// impossible — a picker, a dropdown — so nothing is said for no reason.
  final String? invalidMessage;

  final Widget child;

  const EditOnClose({
    super.key,
    required this.commit,
    required this.child,
    this.invalidMessage,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope<T?>(
      // Blocks only the *system* pops — back gesture and barrier tap — and
      // hands them to us instead. A direct Navigator.pop(value) is unaffected,
      // which is what lets a secondary action ("use the default", "reset")
      // answer with its own value without going through [commit].
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final value = commit();
        final message = invalidMessage;
        if (value == null && message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
          );
        }
        Navigator.of(context).pop(value);
      },
      child: child,
    );
  }
}

/// The single action an apply-on-close editor has. There is deliberately no
/// Cancel beside it — the edit has already been made, and Done only says so.
///
/// It closes through `maybePop`, so it takes the exact same path as the back
/// gesture and the barrier tap and cannot drift from them.
class EditDoneButton extends StatelessWidget {
  /// Disables the button while the entry cannot be stored, so Done is never the
  /// thing that throws an edit away. The other two close paths still commit —
  /// they have to, nothing can block a back gesture — and that is what
  /// `invalidMessage` covers.
  final bool enabled;

  const EditDoneButton({super.key, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FilledButton(
      onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
      child: Text(l.editDone),
    );
  }
}
