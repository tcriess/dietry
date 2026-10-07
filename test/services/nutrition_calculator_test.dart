import 'package:dietry/models/models.dart';
import 'package:dietry/services/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

UserBodyData _body(double weight, WeightGoal goal) => UserBodyData(
      weight: weight,
      height: 180,
      gender: Gender.male,
      age: 40,
      activityLevel: ActivityLevel.values.first,
      weightGoal: goal,
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
