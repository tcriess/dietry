import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/food_item.dart';

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

void main() {
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
