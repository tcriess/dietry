import 'package:dietry/models/food_entry.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:dietry/widgets/quick_estimate_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

QuickEstimate build({
  EstimateBasis basis = EstimateBasis.total,
  double? grams,
  String unit = kUnitGram,
  double calories = 100,
  double protein = 10,
  double fat = 5,
  double carbs = 20,
  double? fiber,
  EstimateLevel level = EstimateLevel.medium,
}) =>
    buildQuickEstimate(
      name: 'Kantinenteller',
      basis: basis,
      grams: grams,
      unit: unit,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      estimateLevel: level,
    );

void main() {
  group('buildQuickEstimate — totals basis', () {
    test('without a weight the figures are the entry, logged as one portion',
        () {
      final e = build(grams: null);

      expect(e.isMeal, isTrue);
      expect(e.amount, 1);
      expect(e.unit, kUnitPortion);
      expect(e.calories, 100);
      expect(e.protein, 10);
      expect(e.amountG, isNull, reason: 'no per-100 basis to recover');
    });

    test('a weight is recorded without rescaling the figures', () {
      final e = build(grams: 250);

      expect(e.isMeal, isFalse);
      expect(e.amount, 250);
      expect(e.unit, kUnitGram);
      expect(e.calories, 100, reason: 'totals are taken as typed');
      expect(e.amountG, 250);
    });

    test('a zero weight is treated as no weight', () {
      final e = build(grams: 0);

      expect(e.isMeal, isTrue);
      expect(e.amount, 1);
      expect(e.unit, kUnitPortion);
    });
  });

  group('buildQuickEstimate — per-100 basis', () {
    test('scales every nutrient by the weight', () {
      final e = build(
        basis: EstimateBasis.per100,
        grams: 250,
        calories: 100,
        protein: 10,
        fat: 5,
        carbs: 20,
        fiber: 2,
      );

      expect(e.calories, closeTo(250, 1e-9));
      expect(e.protein, closeTo(25, 1e-9));
      expect(e.fat, closeTo(12.5, 1e-9));
      expect(e.carbs, closeTo(50, 1e-9));
      expect(e.fiber, closeTo(5, 1e-9));
      expect(e.amount, 250);
      expect(e.amountG, 250);
      expect(e.isMeal, isFalse);
    });

    test('an unset optional nutrient stays unset', () {
      final e = build(basis: EstimateBasis.per100, grams: 250);

      expect(e.fiber, isNull);
      expect(e.sugar, isNull);
      expect(e.sodium, isNull);
      expect(e.saturatedFat, isNull);
    });
  });

  group('buildQuickEstimate — fluids', () {
    test('ml marks the entry as fluid and carries the volume', () {
      final e = build(grams: 330, unit: kUnitMl);

      expect(e.isLiquid, isTrue);
      expect(e.amountMl, 330);
      expect(e.unit, kUnitMl);
    });

    test('grams are never fluid', () {
      final e = build(grams: 330, unit: kUnitGram);

      expect(e.isLiquid, isFalse);
      expect(e.amountMl, isNull);
    });

    test('a weightless entry cannot be fluid — there is no volume', () {
      final e = build(grams: null, unit: kUnitMl);

      expect(e.isLiquid, isFalse);
      expect(e.amountMl, isNull);
      expect(e.unit, kUnitPortion);
    });
  });

  test('the chosen uncertainty rides along untouched', () {
    expect(build(level: EstimateLevel.high).estimateLevel, EstimateLevel.high);
    expect(build(level: EstimateLevel.none).estimateLevel, EstimateLevel.none);
  });
}
