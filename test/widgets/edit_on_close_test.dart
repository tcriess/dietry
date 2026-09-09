import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/widgets/edit_on_close.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [EditOnClose] is the one place the app's "editing has no Save button" rule
/// is implemented, so the thing worth pinning down is that all three ways out
/// of a dialog behave identically. A dialog that committed on Done but dropped
/// the edit on a back gesture would be worse than one with a Save button.

Future<String? Function()> open(
  WidgetTester tester, {
  required String? Function() commit,
  String? invalidMessage,
  bool doneEnabled = true,
  List<Widget> extraActions = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  String? result;
  var returned = false;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<String>(
              context: ctx,
              builder: (dctx) => EditOnClose<String>(
                commit: commit,
                invalidMessage: invalidMessage,
                child: AlertDialog(
                  title: const Text('editor'),
                  actions: [
                    ...extraActions,
                    EditDoneButton(enabled: doneEnabled),
                  ],
                ),
              ),
            );
            returned = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () {
    expect(returned, isTrue, reason: 'dialog never returned');
    return result;
  };
}

void main() {
  testWidgets('Done commits', (t) async {
    final result = await open(t, commit: () => 'value');
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(result(), 'value');
  });

  testWidgets('the back gesture commits the same thing', (t) async {
    final result = await open(t, commit: () => 'value');
    final NavigatorState nav = t.state(find.byType(Navigator).last);
    nav.maybePop();
    await t.pumpAndSettle();
    expect(result(), 'value');
  });

  testWidgets('a tap outside commits the same thing', (t) async {
    final result = await open(t, commit: () => 'value');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(result(), 'value');
  });

  testWidgets('commit runs exactly once per close', (t) async {
    var calls = 0;
    await open(t, commit: () {
      calls++;
      return 'value';
    });
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('there is no Cancel', (t) async {
    await open(t, commit: () => 'value');
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('an unusable entry answers null and says so', (t) async {
    final result = await open(
      t,
      commit: () => null,
      invalidMessage: 'kept the old one',
      doneEnabled: false,
    );
    // Done is disabled, so backing out is the only way out — and it must not
    // pretend the unusable entry was a value.
    final NavigatorState nav = t.state(find.byType(Navigator).last);
    nav.maybePop();
    await t.pumpAndSettle();

    expect(result(), isNull);
    expect(find.text('kept the old one'), findsOneWidget);
  });

  testWidgets('nothing is said when no invalidMessage was given', (t) async {
    // A picker cannot hold an unusable value, so it must not apologise for one.
    await open(t, commit: () => null);
    final NavigatorState nav = t.state(find.byType(Navigator).last);
    nav.maybePop();
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a secondary action answers with its own value, not the field\'s',
      (t) async {
    // "Use the default" / "Reset" pop directly, bypassing commit — that is what
    // lets them mean something the editor's fields cannot express.
    late BuildContext dialogContext;
    final result = await open(
      t,
      commit: () => 'from-the-field',
      extraActions: [
        Builder(builder: (ctx) {
          dialogContext = ctx;
          return TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('reset'),
            child: const Text('Reset'),
          );
        }),
      ],
    );
    await t.tap(find.text('Reset'));
    await t.pumpAndSettle();
    expect(result(), 'reset');
  });

  testWidgets('Done is inert while the entry cannot be stored', (t) async {
    await open(t, commit: () => null, doneEnabled: false);
    final done = t.widget<FilledButton>(
      find.ancestor(of: find.text('Done'), matching: find.byType(FilledButton)),
    );
    expect(done.onPressed, isNull);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget, reason: 'must stay open');
  });
}
