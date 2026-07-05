import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/food_item.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/services/meal_description_parser.dart';
import 'package:dietry/services/meal_suggestion_service.dart';

FoodItem _food({
  double? servingSize,
  List<FoodPortion> portions = const [],
}) {
  final t = DateTime(2026, 1, 1);
  return FoodItem(
    id: 'x',
    name: 'test',
    calories: 100,
    protein: 5,
    fat: 2,
    carbs: 15,
    servingSize: servingSize,
    portions: portions,
    isPublic: true,
    isApproved: true,
    createdAt: t,
    updatedAt: t,
  );
}

double grams(ParsedMealItem i, FoodItem f) =>
    MealSuggestionService.resolveGrams(i, f);

void main() {
  group('resolveGrams', () {
    test('weighed g/ml is used directly', () {
      expect(
          grams(const ParsedMealItem(query: 'r', quantity: 200, portion: 'g'),
              _food()),
          200);
      expect(
          grams(const ParsedMealItem(query: 'm', quantity: 250, portion: 'ml'),
              _food()),
          250);
    });

    test('bare count uses the food primary portion when defined', () {
      final f = _food(portions: const [FoodPortion(name: '1 egg', amountG: 50)]);
      expect(grams(const ParsedMealItem(query: 'egg', quantity: 2), f), 100);
    });

    test('bare count falls back to serving size, then 100 g', () {
      expect(grams(const ParsedMealItem(query: 'x', quantity: 2), _food(servingSize: 80)),
          160);
      expect(grams(const ParsedMealItem(query: 'x', quantity: 1), _food()), 100);
    });

    test('named portion uses the rough default table', () {
      expect(
          grams(
              const ParsedMealItem(query: 'rice', quantity: 2, portion: 'plate'),
              _food()),
          700); // 2 * 350
    });

    test('generic serving prefers serving size', () {
      expect(
          grams(
              const ParsedMealItem(query: 'x', quantity: 1, portion: 'serving'),
              _food(servingSize: 120)),
          120);
    });
  });
}
