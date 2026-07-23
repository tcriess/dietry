import 'package:dietry/l10n/app_localizations_en.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatWeightAmount', () {
    final l = AppLocalizationsEn();

    test('g and ml render tight, with no space', () {
      expect(formatWeightAmount(150, kUnitGram, l), '150g');
      expect(formatWeightAmount(250, kUnitMl, l), '250ml');
    });

    test('a cooked weight renders the localized "cooked" label', () {
      expect(formatWeightAmount(220, kUnitGramCooked, l), '220 g (cooked)');
    });

    test('portion and meal units are left to the caller', () {
      expect(formatWeightAmount(2, 'Scheibe', l), isNull);
      expect(formatWeightAmount(1, 'Portion', l), isNull);
    });
  });

  group('unitToGrams', () {
    test('direct weight units pass through', () {
      expect(unitToGrams(150, kUnitGram), 150);
      expect(unitToGrams(250, kUnitMl), 250);
    });

    test('a cooked weight converts back to the label basis', () {
      expect(unitToGrams(220, kUnitGramCooked, cookedFactor: 2.2),
          closeTo(100, 0.01));
    });

    test('a cooked weight without a factor is unresolvable, not zero', () {
      // Zero would silently log a 0 kcal entry; null makes callers fall back.
      expect(unitToGrams(220, kUnitGramCooked), isNull);
    });

    test('a portion wins over the unit token', () {
      // Portion names are user-authored and may collide with "g".
      expect(
        unitToGrams(2, kUnitGram,
            portion: const FoodPortion(name: 'g', amountG: 50)),
        100,
      );
    });

    test('an unknown unit is unresolvable', () {
      expect(unitToGrams(2, 'Scheibe'), isNull);
    });
  });

  group('isDirectWeightUnit', () {
    test('g and ml are direct, a cooked weight is not', () {
      expect(isDirectWeightUnit(kUnitGram), isTrue);
      expect(isDirectWeightUnit(kUnitMl), isTrue);
      expect(isDirectWeightUnit(kUnitGramCooked), isFalse);
      expect(isDirectWeightUnit('Scheibe'), isFalse);
    });
  });
}
