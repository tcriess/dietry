import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/food_item.dart';
import 'package:dietry/models/food_search_result.dart';

FoodItem _dummyFood({String name = 'Apfel'}) => FoodItem(
      id: '',
      userId: null,
      name: name,
      calories: 52,
      protein: 0.3,
      fat: 0.2,
      carbs: 14,
      portions: const [],
      source: 'OpenFoodFacts',
      isPublic: false,
      isApproved: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('FoodSearchResult', () {
    test('hasMicros ist false wenn micros leer', () {
      final result = FoodSearchResult(food: _dummyFood());
      expect(result.hasMicros, isFalse);
      expect(result.micros, isEmpty);
    });

    test('hasMicros ist true wenn micros vorhanden', () {
      final result = FoodSearchResult(
        food: _dummyFood(),
        micros: const {'vitamin_c_mg': 4.6, 'calcium_mg': 6.0},
      );
      expect(result.hasMicros, isTrue);
      expect(result.micros['vitamin_c_mg'], 4.6);
      expect(result.micros['calcium_mg'], 6.0);
    });

    test('food ist zugänglich', () {
      final food = _dummyFood(name: 'Banane');
      final result = FoodSearchResult(food: food);
      expect(result.food.name, 'Banane');
      expect(result.food.calories, 52);
    });

    test('micros Default ist unveränderliche leere Map', () {
      final result = FoodSearchResult(food: _dummyFood());
      expect(result.micros, isEmpty);
      // const Map ist unmodifiable
      expect(() => result.micros['x'] = 1.0, throwsA(anything));
    });

    test('micros enthält korrekte DB-Spaltennamen-Schlüssel', () {
      const validKeys = {
        'vitamin_a_mcg',
        'vitamin_d_mcg',
        'calcium_mg',
        'iron_mg',
        'saturated_fat_g',
        'omega_3_g',
        'cholesterol_mg',
      };
      final result = FoodSearchResult(
        food: _dummyFood(),
        micros: {for (final k in validKeys) k: 1.0},
      );
      for (final key in validKeys) {
        expect(result.micros.containsKey(key), isTrue);
      }
    });

    group('Praxisbeispiele — OFF-Produkt', () {
      test('Milch — Calcium und Vitamin D vorhanden', () {
        final result = FoodSearchResult(
          food: _dummyFood(name: 'Vollmilch'),
          micros: {
            'calcium_mg': 120.0,
            'vitamin_d_mcg': 0.1,
            'vitamin_b12_mcg': 0.45,
          },
        );
        expect(result.hasMicros, isTrue);
        expect(result.micros['calcium_mg'], 120.0);
        expect(result.micros['vitamin_b12_mcg'], 0.45);
      });

      test('Lachs — Omega-3 und Vitamin D vorhanden', () {
        final result = FoodSearchResult(
          food: _dummyFood(name: 'Lachs'),
          micros: {
            'omega_3_g': 2.3,
            'vitamin_d_mcg': 11.0,
            'selenium_mcg': 35.0,
          },
        );
        expect(result.micros['omega_3_g'], 2.3);
        expect(result.micros['selenium_mcg'], 35.0);
      });
    });
  });
}
