import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/widgets/exercise_credit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog has to answer three different questions with one widget, and the
/// distinction that matters is between "the user chose a number", "the user
/// chose to inherit" and "the user backed out" — three outcomes the caller
/// stores three different ways, and a null factor is *not* the same as no
/// answer at all.

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

  testWidgets('saving returns the entered percentage as a factor', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '60');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(result()!.factor, 0.6);
  });

  testWidgets('inheriting answers with a null factor, not with no answer',
      (t) async {
    final result = await open(t, current: 0.25, inherited: 0.5);
    await t.tap(find.text('Inherit'));
    await t.pumpAndSettle();
    expect(result(), isNotNull);
    expect(result()!.factor, isNull);
  });

  testWidgets('cancelling answers with nothing at all', (t) async {
    final result = await open(t, current: 0.25, inherited: 0.5);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(result(), isNull);
  });

  testWidgets('an out-of-range entry is refused and keeps the dialog open',
      (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '900');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Enter a value between 0 and 200'), findsOneWidget);

    // …and a corrected entry then goes through.
    await t.enterText(find.byType(TextField), '90');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(result()!.factor, 0.9);
  });

  testWidgets('zero is a real answer, not an empty one', (t) async {
    final result = await open(t, current: null, inherited: 1.0);
    await t.enterText(find.byType(TextField), '0');
    await t.tap(find.text('Save'));
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
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      expect(called, isTrue);
      expect(seen, 0.8);
    });
  });
}
