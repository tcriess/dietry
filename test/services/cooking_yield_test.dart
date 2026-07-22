import 'package:dietry/models/food_entry.dart' show EstimateLevel;
import 'package:dietry/models/food_item.dart';
import 'package:dietry/services/cooking_yield.dart';
import 'package:flutter_test/flutter_test.dart';

FoodItem food(String name, {String? category}) => FoodItem(
      id: 'x',
      name: name,
      calories: 350,
      protein: 12,
      fat: 1.5,
      carbs: 71,
      category: category,
      isPublic: true,
      isApproved: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('CookingYield.defaultFor', () {
    test('dry pasta gets the absorption factor', () {
      final info = CookingYield.defaultFor(food('Spaghetti No. 5'))!;
      expect(info.factor, 2.2);
      expect(info.kind, YieldKind.absorption);
      expect(info.uncertainty, EstimateLevel.low);
    });

    test('matches inside German compounds', () {
      expect(CookingYield.defaultFor(food('Vollkornnudeln'))?.factor, 2.2);
      expect(CookingYield.defaultFor(food('Haferflocken'))?.factor, 2.6);
    });

    test('matches the English and Spanish spellings', () {
      expect(CookingYield.defaultFor(food('Whole Wheat Spaghetti'))?.factor, 2.2);
      expect(CookingYield.defaultFor(food('Espaguetis integrales'))?.factor, 2.2);
      expect(CookingYield.defaultFor(food('Arroz basmati'))?.factor, 2.6);
    });

    test('rice matches as a word, not inside unrelated words', () {
      expect(CookingYield.defaultFor(food('Basmati Reis'))?.factor, 2.6);
      // "Preiselbeere" contains the substring "reis" — must not match.
      expect(CookingYield.defaultFor(food('Preiselbeeren')), isNull);
    });

    test('meat is offered but flagged as less certain', () {
      final info = CookingYield.defaultFor(food('Hähnchenbrustfilet'))!;
      expect(info.factor, 0.73);
      expect(info.kind, YieldKind.fatLoss);
      expect(info.uncertainty, EstimateLevel.medium);
    });

    test('already-cooked foods are skipped (no double conversion)', () {
      expect(CookingYield.defaultFor(food('Reis (gekocht)')), isNull);
      expect(CookingYield.defaultFor(food('Kartoffel (gekocht)')), isNull);
      expect(CookingYield.defaultFor(food('Pasta, cooked')), isNull);
      expect(CookingYield.defaultFor(food('Arroz cocido')), isNull);
    });

    test('composite and pre-cooked products are skipped', () {
      expect(CookingYield.defaultFor(food('Nudelsalat')), isNull);
      expect(CookingYield.defaultFor(food('Hühnersuppe')), isNull);
      expect(CookingYield.defaultFor(food('Kidneybohnen (Dose)')), isNull);
      expect(CookingYield.defaultFor(food('Pasta-Sauce Bolognese')), isNull);
    });

    test('unrelated foods get no factor', () {
      expect(CookingYield.defaultFor(food('Vollmilch 3,5%')), isNull);
      expect(CookingYield.defaultFor(food('Gouda')), isNull);
      expect(CookingYield.defaultFor(food('Apfel')), isNull);
    });
  });

  group('CookingYield.alreadyCooked', () {
    test('detects cooked markers across languages', () {
      expect(CookingYield.alreadyCooked(food('Ei (gekocht)')), isTrue);
      expect(CookingYield.alreadyCooked(food('Chicken, roasted')), isTrue);
      expect(CookingYield.alreadyCooked(food('Spaghetti')), isFalse);
    });
  });

  group('CookingYield.toRawGrams', () {
    test('converts a cooked weight back to the label basis', () {
      // 220 g of cooked pasta came from ~100 g dry.
      expect(CookingYield.toRawGrams(220, 2.2), closeTo(100, 0.01));
      // 100 g of grilled chicken came from ~137 g raw.
      expect(CookingYield.toRawGrams(100, 0.73), closeTo(136.99, 0.01));
    });

    test('degrades safely on a zero factor', () {
      expect(CookingYield.toRawGrams(150, 0), 150);
    });
  });

  group('normalize', () {
    test('folds the accents our food names contain', () {
      expect(CookingYield.normalize('Hähnchen'), 'hahnchen');
      expect(CookingYield.normalize('GRIEß'), 'griess');
      expect(CookingYield.normalize('Espinacas'), 'espinacas');
    });
  });
}
