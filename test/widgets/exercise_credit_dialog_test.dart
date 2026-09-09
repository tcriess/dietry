import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/widgets/exercise_credit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog has to answer three different questions with one widget. It
/// applies on close (see [EditOnClose]): there is no Save and no Cancel, and
/// every way out — Done, the back gesture, a tap outside — has to commit the
/// same thing. A dialog that saved on Done but dropped the edit on a back
/// gesture would be worse than one with a Save button, so all three paths are
/// exercised here.
///
/// A null result means "the entry was unusable, keep what you had"; a
/// [ExerciseCreditChoice] carrying a null factor means "inherit". They are
/// different answers and the caller stores them differently.

Future<ExerciseCreditChoice? Function()> open(
  WidgetTester tester, {
  double? current,
  double inherited = 1.0,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  ExerciseCreditChoice? result;
  var returned = false;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showExerciseCreditDialog(
              ctx,
              title: 'Credit',
              current: current,
              inheritedFactor: inherited,
              inheritLabel: 'Inherit',
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
  testWidgets('opens on the value in force, not on an empty field', (t) async {
    // No own value: the field must still show what currently applies, so the
    // user edits a number rather than guessing one.
    await open(t, current: null, inherited: 0.5);
    expect(find.widgetWithText(TextField, '50'), findsOneWidget);
  });

  testWidgets('opens on its own value when it has one', (t) async {
    await open(t, current: 0.25, inherited: 0.5);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
  });

  testWidgets('Done applies the entered percentage as a factor', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '60');
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(result()!.factor, 0.6);
  });

  testWidgets('the back gesture applies the edit too', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '40');
    final NavigatorState nav = t.state(find.byType(Navigator).last);
    nav.maybePop();
    await t.pumpAndSettle();
    expect(result()!.factor, 0.4);
  });

  testWidgets('a tap outside applies the edit too', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '35');
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
    expect(result()!.factor, 0.35);
  });

  testWidgets('there is no Save and no Cancel', (t) async {
    await open(t, current: 0.25, inherited: 0.5);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('inheriting answers with a null factor, not with no answer',
      (t) async {
    final result = await open(t, current: 0.25, inherited: 0.5);
    await t.tap(find.text('Inherit'));
    await t.pumpAndSettle();
    expect(result(), isNotNull);
    expect(result()!.factor, isNull);
  });

  testWidgets('an out-of-range entry marks the field and disables Done',
      (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '900');
    await t.pumpAndSettle();

    expect(find.text('Enter a value between 0 and 200'), findsOneWidget);
    final done = t.widget<FilledButton>(
        find.ancestor(of: find.text('Done'), matching: find.byType(FilledButton)));
    expect(done.onPressed, isNull, reason: 'Done must not throw the edit away');

    // …and a corrected entry then goes through.
    await t.enterText(find.byType(TextField), '90');
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(result()!.factor, 0.9);
  });

  testWidgets('backing out of an unusable entry keeps the previous value',
      (t) async {
    // Done is disabled here, so the back gesture is the only way out — and it
    // must not store 900%. The caller reads null as "leave it alone".
    final result = await open(t, current: 0.5, inherited: 1.0);
    await t.enterText(find.byType(TextField), '900');
    await t.pumpAndSettle();
    final NavigatorState nav = t.state(find.byType(Navigator).last);
    nav.maybePop();
    await t.pumpAndSettle();
    expect(result(), isNull);
  });

  testWidgets('zero is a real answer, not an empty one', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '0');
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(result()!.factor, 0);
  });

  group('ExerciseCreditField', () {
    Future<void> pumpField(
      WidgetTester tester, {
      required double? value,
      required double inherited,
      required ValueChanged<double?> onChanged,
    }) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExerciseCreditField(
            value: value,
            inheritedFactor: inherited,
            onChanged: onChanged,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('says it follows the day, and with what number', (t) async {
      await pumpField(t, value: null, inherited: 0.5, onChanged: (_) {});
      expect(find.text('Follow the day (50%)'), findsOneWidget);
    });

    testWidgets('says when the activity overrides the day', (t) async {
      await pumpField(t, value: 0.25, inherited: 0.5, onChanged: (_) {});
      expect(find.text('25% · this activity only'), findsOneWidget);
    });

    testWidgets('reports the chosen factor back to the form', (t) async {
      double? seen;
      var called = false;
      await pumpField(t,
          value: null,
          inherited: 0.5,
          onChanged: (v) {
            seen = v;
            called = true;
          });

      await t.tap(find.byType(InkWell));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '80');
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();

      expect(called, isTrue);
      expect(seen, 0.8);
    });
  });
}
