import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/food_item.dart';
import 'package:dietry/models/food_portion.dart';

FoodItem _food({
  String? brand,
  String? category,
  String? source,
}) =>
    FoodItem(
      id: '',
      name: 'Pasta',
      calories: 350,
      protein: 12,
      fat: 1.5,
      carbs: 71,
      brand: brand,
      category: category,
      source: source,
      isPublic: false,
      isApproved: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

FoodItem _bar() => FoodItem(
      id: 'x',
      name: 'Protein Riegel',
      // The values a 25 g bar's label carries, sitting in the per-100 g fields.
      calories: 105,
      protein: 6.2,
      fat: 5,
      carbs: 11.6,
      fiber: 0.8,
      sugar: 0.3,
      sodium: 0.07,
      saturatedFat: 3.1,
      portions: const [FoodPortion(name: '1 Riegel', amountG: 25)],
      isPublic: false,
      isApproved: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('FoodItem.rescaleNutrition', () {
    test('puts a per-portion label back on a per-100 g basis', () {
      final fixed = _bar().rescaleNutrition(100 / 25);

      expect(fixed.calories, 420);
      expect(fixed.protein, closeTo(24.8, 0.001));
      expect(fixed.fat, 20);
      expect(fixed.carbs, closeTo(46.4, 0.001));
    });

    test('scales the optional nutrients too, and keeps missing ones missing', () {
      final fixed = _bar().rescaleNutrition(4);

      expect(fixed.fiber, closeTo(3.2, 0.001));
      expect(fixed.sugar, closeTo(1.2, 0.001));
      expect(fixed.sodium, closeTo(0.28, 0.001));
      expect(fixed.saturatedFat, closeTo(12.4, 0.001));
      expect(_food().rescaleNutrition(4).fiber, isNull);
    });

    test('leaves everything that is not a nutrient alone', () {
      final fixed = _bar().rescaleNutrition(4);

      expect(fixed.id, 'x');
      expect(fixed.name, 'Protein Riegel');
      expect(fixed.portions, _bar().portions);
    });
  });

  group('FoodItem.provenanceSummary', () {
    test('is null when nothing distinguishing is known', () {
      expect(_food().provenanceSummary, isNull);
    });

    test('empty strings count as unknown', () {
      expect(_food(brand: '', category: '', source: '').provenanceSummary,
          isNull);
    });

    test('brand alone is enough', () {
      expect(_food(brand: 'Barilla').provenanceSummary, 'Barilla');
    });

    test('joins brand, category and source in that order', () {
      final food = _food(
        brand: 'Barilla',
        category: 'Nudeln',
        source: 'OpenFoodFacts',
      );
      expect(food.provenanceSummary, 'Barilla · Nudeln · OpenFoodFacts');
    });

    test('skips a missing middle part without leaving a stray separator', () {
      expect(_food(brand: 'Barilla', source: 'USDA').provenanceSummary,
          'Barilla · USDA');
    });

    // A user-created food already carries the 👤 badge in the list; repeating
    // "Custom" in the detail line would be noise.
    test('drops a Custom source', () {
      expect(_food(brand: 'Barilla', source: 'Custom').provenanceSummary,
          'Barilla');
      expect(_food(source: 'Custom (user)').provenanceSummary, isNull);
    });
  });
}
