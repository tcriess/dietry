import 'package:dietry/models/food_item.dart';
import 'package:dietry/screens/edit_food_entry_screen.dart';
import 'package:dietry/utils/number_utils.dart';
import 'package:flutter_test/flutter_test.dart';

FoodItem food({
  double calories = 539,
  double protein = 6.34,
  double fat = 30.9,
  double carbs = 57.5,
  double? fiber,
  double? sugar,
  double? sodium,
  double? saturatedFat,
}) =>
    FoodItem(
      id: 'f1',
      userId: 'u1',
      name: 'Nuss-Nougat-Creme',
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      saturatedFat: saturatedFat,
      isPublic: false,
      isApproved: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// The eight fields as the edit screen fills them from a food, i.e. what the
/// user sees before touching anything.
Per100Fields fieldsOf(FoodItem f) => (
      calories: per100FieldText(f.calories, 0),
      protein: per100FieldText(f.protein, 1),
      fat: per100FieldText(f.fat, 1),
      carbs: per100FieldText(f.carbs, 1),
      fiber: per100FieldText(f.fiber, 1),
      sugar: per100FieldText(f.sugar, 1),
      sodium: per100FieldText(f.sodium, 1),
      saturatedFat: per100FieldText(f.saturatedFat, 1),
    );

/// Reproduces the round trip the edit screen puts a value through: food →
/// entry total for [grams] → back to a per-100 field.
String roundTrip(double per100, double grams, int digits) =>
    per100FieldText(toPer100g(scaleToTotal(per100, grams), grams), digits);

void main() {
  group('per100DiffersFromFood', () {
    test('untouched fields are not a correction', () {
      final f = food();
      expect(per100DiffersFromFood(f, fieldsOf(f)), isFalse);
    });

    test('a value that survived the entry round trip is not a correction', () {
      // 6.34 g protein of a 37 g portion is stored as 2.3458 g and read back as
      // "6.3" — the same string the food itself renders, so nothing changed.
      final f = food();
      final fields = (
        calories: roundTrip(f.calories, 37, 0),
        protein: roundTrip(f.protein, 37, 1),
        fat: roundTrip(f.fat, 37, 1),
        carbs: roundTrip(f.carbs, 37, 1),
        fiber: '',
        sugar: '',
        sodium: '',
        saturatedFat: '',
      );
      expect(per100DiffersFromFood(f, fields), isFalse);
    });

    test('an edited calorie value is a correction', () {
      final f = food();
      final fields = fieldsOf(f);
      expect(
        per100DiffersFromFood(f, (
          calories: '546',
          protein: fields.protein,
          fat: fields.fat,
          carbs: fields.carbs,
          fiber: fields.fiber,
          sugar: fields.sugar,
          sodium: fields.sodium,
          saturatedFat: fields.saturatedFat,
        )),
        isTrue,
      );
    });

    test('filling in an optional nutrient the food lacks is a correction', () {
      final f = food();
      final fields = fieldsOf(f);
      expect(fields.fiber, isEmpty);
      expect(
        per100DiffersFromFood(f, (
          calories: fields.calories,
          protein: fields.protein,
          fat: fields.fat,
          carbs: fields.carbs,
          fiber: '3.4',
          sugar: fields.sugar,
          sodium: fields.sodium,
          saturatedFat: fields.saturatedFat,
        )),
        isTrue,
      );
    });

    test('clearing an optional nutrient the food has is a correction', () {
      final f = food(fiber: 3.4);
      final fields = fieldsOf(f);
      expect(fields.fiber, '3.4');
      expect(
        per100DiffersFromFood(f, (
          calories: fields.calories,
          protein: fields.protein,
          fat: fields.fat,
          carbs: fields.carbs,
          fiber: '',
          sugar: fields.sugar,
          sodium: fields.sodium,
          saturatedFat: fields.saturatedFat,
        )),
        isTrue,
      );
    });

    test('surrounding whitespace is not a correction', () {
      final f = food();
      final fields = fieldsOf(f);
      expect(
        per100DiffersFromFood(f, (
          calories: ' ${fields.calories} ',
          protein: fields.protein,
          fat: fields.fat,
          carbs: fields.carbs,
          fiber: fields.fiber,
          sugar: fields.sugar,
          sodium: fields.sodium,
          saturatedFat: fields.saturatedFat,
        )),
        isFalse,
      );
    });
  });

  group('per100FieldText', () {
    test('renders calories whole and the rest to one decimal', () {
      expect(per100FieldText(539.0, 0), '539');
      expect(per100FieldText(6.34, 1), '6.3');
    });

    test('an absent value renders as an empty field', () {
      expect(per100FieldText(null, 1), '');
    });
  });
}
