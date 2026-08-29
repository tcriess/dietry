import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/l10n/app_localizations_de.dart';
import 'package:dietry/l10n/app_localizations_en.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:dietry/widgets/portion_size_dialog.dart';
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

  test('the add-portion sentinel cannot collide with a portion name', () {
    // Sentinel and portion names share one dropdown, so the sentinel has to be
    // something no user could ever type into the name field.
    expect(kAddPortionValue.codeUnitAt(0), 0);
    expect([kUnitGram, kUnitMl, kUnitGramCooked],
        isNot(contains(kAddPortionValue)));
  });
}
