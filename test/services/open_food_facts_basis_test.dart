import 'package:dietry/models/food_search_result.dart';
import 'package:dietry/services/open_food_facts_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A product record shaped like Open Food Facts', with only the fields the
/// parser reads. Nutriment values are given per 100 g unless [per] says
/// otherwise.
Map<String, dynamic> product({
  String name = 'Riegel',
  Map<String, dynamic> nutriments = const {},
  String? per,
  num? servingQuantity,
  String? servingUnit,
}) =>
    {
      'code': '4011800003395',
      'product_name': name,
      'nutriments': nutriments,
      if (per != null) 'nutrition_data_per': per,
      if (servingQuantity != null) 'serving_quantity': servingQuantity,
      if (servingUnit != null) 'serving_quantity_unit': servingUnit,
    };

Map<String, dynamic> nutriments({
  required num kcal,
  num protein = 5,
  num fat = 5,
  num carbs = 10,
  String suffix = '_100g',
}) =>
    {
      'energy-kcal$suffix': kcal,
      'proteins$suffix': protein,
      'fat$suffix': fat,
      'carbohydrates$suffix': carbs,
    };

void main() {
  final service = OpenFoodFactsService();

  group('nutrition basis', () {
    test('per-100 g values are taken as they are', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 420, protein: 25, fat: 20, carbs: 46),
        per: '100g',
        servingQuantity: 25,
      ));

      expect(r!.food.calories, 420);
      expect(r.food.protein, 25);
    });

    test('a missing nutrition_data_per means per 100 g', () {
      // By far the common case: OFF omits the field for most products.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 420, protein: 25, fat: 20, carbs: 46),
      ));

      expect(r!.food.calories, 420);
    });

    test('per-serving values are converted with the serving weight', () {
      // The contributor entered the 25 g bar's label and OFF could not convert
      // it: only the *_serving fields carry the numbers.
      final r = service.parseProduct(product(
        nutriments: nutriments(
            kcal: 105, protein: 6.2, fat: 5, carbs: 11.6, suffix: '_serving'),
        per: 'serving',
        servingQuantity: 25,
        servingUnit: 'g',
      ));

      expect(r!.food.calories, closeTo(420, 0.01));
      expect(r.food.protein, closeTo(24.8, 0.01));
      expect(r.food.carbs, closeTo(46.4, 0.01));
    });

    test('OFF\'s own per-100 g conversion wins over ours', () {
      // Both sets present: the converted one is what OFF stands behind.
      final r = service.parseProduct(product(
        nutriments: {
          ...nutriments(kcal: 420, protein: 24.8, fat: 20, carbs: 46.4),
          ...nutriments(
              kcal: 105, protein: 6.2, fat: 5, carbs: 11.6, suffix: '_serving'),
        },
        per: 'serving',
        servingQuantity: 25,
        servingUnit: 'g',
      ));

      expect(r!.food.calories, 420);
    });

    test('per-serving values without a serving weight are refused', () {
      // Nothing says what these numbers are per, and guessing "100 g" is how a
      // 25 g bar ends up logged at a quarter of its calories.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 105, suffix: '_serving'),
        per: 'serving',
      ));

      expect(r, isNull);
    });

    test('a serving stated in an unusable unit is not a serving weight', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 105, suffix: '_serving'),
        per: 'serving',
        servingQuantity: 1,
        servingUnit: 'oz',
      ));

      expect(r, isNull);
    });

    test('micronutrients follow the same basis as the macros', () {
      final r = service.parseProduct(product(
        nutriments: {
          ...nutriments(
              kcal: 105, protein: 6.2, fat: 5, carbs: 11.6, suffix: '_serving'),
          'calcium_serving': 0.05, // 50 mg per 25 g bar
          'calcium_unit': 'g',
        },
        per: 'serving',
        servingQuantity: 25,
        servingUnit: 'g',
      ));

      expect(r!.micros['calcium_mg'], closeTo(200, 0.01));
    });
  });

  group('serving size', () {
    test('becomes the serving size and a named portion', () {
      // The weight off the packet is the portion the user would otherwise have
      // to establish and type in by hand after scanning.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 420, protein: 25, fat: 20, carbs: 46),
        servingQuantity: 25,
        servingUnit: 'g',
      ));

      expect(r!.food.servingSize, 25);
      expect(r.food.servingUnit, 'g');
      expect(r.food.portions.single.amountG, 25);
    });

    test('is left out when OFF does not know it', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 420, protein: 25, fat: 20, carbs: 46),
      ));

      expect(r!.food.servingSize, isNull);
      expect(r.food.portions, isEmpty);
    });

    test('a sub-gram serving is treated as unknown', () {
      // Scaling half a gram up to 100 g multiplies any typo by two hundred.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 420, protein: 25, fat: 20, carbs: 46),
        servingQuantity: 0.5,
        servingUnit: 'g',
      ));

      expect(r!.food.portions, isEmpty);
    });
  });

  group('plausibility', () {
    test('sound values raise nothing', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 481, protein: 8, fat: 22.5, carbs: 60.5),
      ));

      expect(r!.warnings, isEmpty);
    });

    test('macros weighing more than 100 g are impossible', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 700, protein: 40, fat: 30, carbs: 60),
      ));

      expect(r!.warnings, contains(NutritionDataWarning.impossibleValues));
    });

    test('more energy than pure fat is impossible', () {
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 1200, protein: 0, fat: 99, carbs: 0),
      ));

      expect(r!.warnings, contains(NutritionDataWarning.impossibleValues));
    });

    test('energy that does not match the macros is flagged', () {
      // 20 g of fat alone is 180 kcal; 60 cannot be right.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 60, protein: 10, fat: 20, carbs: 30),
      ));

      expect(r!.warnings, contains(NutritionDataWarning.energyMismatch));
    });

    test('a whole label mis-scaled by the same factor passes every check', () {
      // The Corny bar this was found on: the 25 g figures sit in the per-100 g
      // column, self-consistent and undetectable by arithmetic. Documented so
      // the limit of these checks is not mistaken for a gap in them.
      final r = service.parseProduct(product(
        nutriments: nutriments(kcal: 105, protein: 6.2, fat: 5, carbs: 11.6),
        per: '100g',
        servingQuantity: 25,
        servingUnit: 'g',
      ));

      expect(r!.warnings, isEmpty);
    });
  });
}
