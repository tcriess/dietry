import 'package:dietry/models/models.dart';
import 'package:dietry/services/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

UserBodyData _body(double weight, WeightGoal goal, {double? bodyFat}) =>
    UserBodyData(
      weight: weight,
      height: 180,
      gender: Gender.male,
      age: 40,
      activityLevel: ActivityLevel.values.first,
      weightGoal: goal,
      bodyFatPercentage: bodyFat,
    );

void main() {
  group('protein', () {
    test('uses actual weight below BMI 25', () {
      final m = NutritionCalculator.calculateMacros(_body(70, WeightGoal.maintain));
      expect(m.protein, closeTo(84, 0.01));
    });

    test('caps reference weight at BMI 25', () {
      // 180 cm → 81 kg at BMI 25
      final m = NutritionCalculator.calculateMacros(_body(107, WeightGoal.lose));
      expect(m.protein, closeTo(81 * 1.5, 0.01));
    });
  });

  group('body fat', () {
    test('BMR switches to Katch-McArdle', () {
      // 100 kg at 30 % → 70 kg lean mass
      final data = _body(100, WeightGoal.maintain, bodyFat: 30);
      expect(NutritionCalculator.calculateBMR(data), closeTo(370 + 21.6 * 70, 0.01));
    });

    test('protein reference from lean mass', () {
      // 70 kg lean mass at 20 % fat → 87.5 kg, beats the BMI-25 cap
      final m = NutritionCalculator.calculateMacros(
          _body(100, WeightGoal.lose, bodyFat: 30));
      expect(m.protein, closeTo(87.5 * 1.5, 0.01));
    });

    test('lean users keep their actual weight', () {
      final m = NutritionCalculator.calculateMacros(
          _body(75, WeightGoal.maintain, bodyFat: 12));
      expect(m.protein, closeTo(75 * 1.2, 0.01));
    });

    test('implausible values are ignored', () {
      final data = _body(80, WeightGoal.maintain, bodyFat: 0);
      expect(NutritionCalculator.leanBodyMass(data), isNull);
    });
  });

  group('water', () {
    test('25 ml/kg rounded to 250', () {
      expect(NutritionCalculator.calculateWaterGoal(83), 2000);
    });

    test('clamped to 1500–2500', () {
      expect(NutritionCalculator.calculateWaterGoal(40), 1500);
      expect(NutritionCalculator.calculateWaterGoal(140), 2500);
    });
  });
}
