import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/l10n/app_localizations_de.dart';
import 'package:dietry/l10n/app_localizations_en.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:dietry/widgets/portion_size_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();

  List<String> reserved(AppLocalizations l) => [
        unitLabel(kUnitGram, l, distinguishRaw: true),
        unitLabel(kUnitGramCooked, l),
      ];

  group('validatePortionName', () {
    const existing = [
      FoodPortion(name: '1 Scheibe', amountG: 30),
      FoodPortion(name: '1 Glas', amountG: 200),
    ];

    test('accepts a fresh name', () {
      expect(
        validatePortionName('1 Riegel', existing, reservedLabels: reserved(en)),
        isNull,
      );
    });

    test('rejects empty and whitespace-only names', () {
      expect(
        validatePortionName('', existing, reservedLabels: reserved(en)),
        PortionNameError.empty,
      );
      expect(
        validatePortionName('   ', existing, reservedLabels: reserved(en)),
        PortionNameError.empty,
      );
    });

    test('rejects a duplicate regardless of case or surrounding space', () {
      expect(
        validatePortionName('1 Scheibe', existing, reservedLabels: reserved(en)),
        PortionNameError.duplicate,
      );
      expect(
        validatePortionName('  1 scheibe ', existing,
            reservedLabels: reserved(en)),
        PortionNameError.duplicate,
      );
    });

    test('rejects the built-in unit tokens', () {
      for (final unit in [kUnitGram, kUnitMl, kUnitGramCooked]) {
        expect(
          validatePortionName(unit, existing, reservedLabels: reserved(en)),
          PortionNameError.reserved,
          reason: unit,
        );
        expect(
          validatePortionName(unit.toUpperCase(), existing,
              reservedLabels: reserved(en)),
          PortionNameError.reserved,
          reason: unit,
        );
      }
    });

    test('rejects the localized labels the dropdown already shows', () {
      // Both of these sit in the unit dropdown next to the portions; a portion
      // sharing one would give DropdownButton two items with the same value.
      expect(
        validatePortionName('g (cooked)', existing,
            reservedLabels: reserved(en)),
        PortionNameError.reserved,
      );
      final de = AppLocalizationsDe();
      expect(
        validatePortionName('g (gekocht)', existing,
            reservedLabels: reserved(de)),
        PortionNameError.reserved,
      );
    });

    test('the same name is fine for a food that has no portions yet', () {
      expect(
        validatePortionName('1 Scheibe', const [],
            reservedLabels: reserved(en)),
        isNull,
      );
    });
  });

  group('the "values are for this amount" correction', () {
    /// Opens the dialog and returns what it hands back once [act] has filled it
    /// in and saved.
    Future<NewPortion?> run(
      WidgetTester tester, {
      double? caloriesPer100g,
      double? initialAmount,
      required Future<void> Function(WidgetTester tester) act,
    }) async {
      NewPortion? result;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddPortionSizeDialog(
                  context,
                  existing: const [],
                  initialAmount: initialAmount,
                  caloriesPer100g: caloriesPer100g,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act(tester);
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> fillIn(WidgetTester tester, {required String amount}) async {
      await tester.enterText(find.byType(TextField).first, '1 Riegel');
      await tester.enterText(find.byType(TextField).last, amount);
      await tester.pumpAndSettle();
    }

    testWidgets('is not offered for a food with no values to rewrite',
        (tester) async {
      await run(tester, act: (t) async {
        expect(find.byType(CheckboxListTile), findsNothing);
        await fillIn(t, amount: '25');
        await t.tap(find.text('Save'));
      });
    });

    testWidgets('previews what the correction would produce', (tester) async {
      // The bar this was found on: 105 kcal in the per-100 g column is the
      // 25 g packet's own figure, and 420 is what it should read.
      await run(tester, caloriesPer100g: 105, initialAmount: 25,
          act: (t) async {
        expect(find.textContaining('420'), findsOneWidget);
        await fillIn(t, amount: '25');
        await t.tap(find.text('Save'));
      });
    });

    testWidgets('is off unless the user asks for it', (tester) async {
      final result =
          await run(tester, caloriesPer100g: 105, act: (t) async {
        await fillIn(t, amount: '25');
        await t.tap(find.text('Save'));
      });

      expect(result!.rebaseNutrition, isFalse);
      expect(result.portion.amountG, 25);
    });

    testWidgets('comes back with the portion when ticked', (tester) async {
      final result =
          await run(tester, caloriesPer100g: 105, act: (t) async {
        await fillIn(t, amount: '25');
        await t.tap(find.byType(CheckboxListTile));
        await t.pumpAndSettle();
        await t.tap(find.text('Save'));
      });

      expect(result!.rebaseNutrition, isTrue);
      expect(result.portion.name, '1 Riegel');
      expect(result.portion.amountG, 25);
    });
  });

  test('the add-portion sentinel cannot collide with a portion name', () {
    // Sentinel and portion names share one dropdown, so the sentinel has to be
    // something no user could ever type into the name field.
    expect(kAddPortionValue.codeUnitAt(0), 0);
    expect([kUnitGram, kUnitMl, kUnitGramCooked],
        isNot(contains(kAddPortionValue)));
  });
}
