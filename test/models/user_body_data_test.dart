import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/user_body_data.dart';

void main() {
  group('UserBodyData Model', () {
    test('fromJson sollte valides Objekt erstellen', () {
      final json = {
        'id': 'body-123',
        'weight': 75.5,
        'height': 180.0,
        'gender': 'male',
        'age': 34,
        'activity_level': 'active',
        'weight_goal': 'maintain',
        'measured_at': '2026-03-24',
      };

      final bodyData = UserBodyData.fromJson(json);

      expect(bodyData.id, 'body-123');
      expect(bodyData.weight, 75.5);
      expect(bodyData.height, 180.0);
      expect(bodyData.gender, Gender.male);
      expect(bodyData.age, 34);
      expect(bodyData.activityLevel, ActivityLevel.active);
      expect(bodyData.weightGoal, WeightGoal.maintain);
    });

    test('toJson sollte korrektes JSON erstellen', () {
      final bodyData = UserBodyData(
        id: 'body-123',
        weight: 70.0,
        height: 175.0,
        gender: Gender.female,
        age: 28,
        activityLevel: ActivityLevel.moderate,
        weightGoal: WeightGoal.lose,
        measuredAt: DateTime(2026, 3, 24),
      );

      final json = bodyData.toJson();

      expect(json['id'], 'body-123');
      expect(json['weight'], 70.0);
      expect(json['height'], 175.0);
      expect(json['gender'], 'female');
      expect(json['age'], 28);
      expect(json['activity_level'], 'moderate');
      expect(json['weight_goal'], 'lose');
      expect(json['measured_at'], '2026-03-24');
    });

    test('Gender Enum sollte Display Names haben', () {
      expect(Gender.male.displayName, 'Männlich');
      expect(Gender.female.displayName, 'Weiblich');
    });

    test('ActivityLevel sollte korrekte Multipliers haben', () {
      expect(ActivityLevel.sedentary.multiplier, 1.2);
      expect(ActivityLevel.light.multiplier, 1.375);
      expect(ActivityLevel.moderate.multiplier, 1.55);
      expect(ActivityLevel.active.multiplier, 1.725);
      expect(ActivityLevel.veryActive.multiplier, 1.9);
    });

    test('ActivityLevel sollte Display Names haben', () {
      expect(ActivityLevel.sedentary.displayName, contains('Wenig Bewegung'));
      expect(ActivityLevel.active.displayName, contains('Sehr aktiv'));
    });

    test('WeightGoal sollte Display Names haben', () {
      expect(WeightGoal.lose.displayName, contains('Abnehmen'));
      expect(WeightGoal.maintain.displayName, contains('Gewicht halten'));
      expect(WeightGoal.gain.displayName, contains('Zunehmen'));
    });

    test('WeightGoal sollte korrekte Calorie Adjustments haben', () {
      expect(WeightGoal.lose.calorieAdjustment, -500);
      expect(WeightGoal.maintain.calorieAdjustment, 0);
      expect(WeightGoal.gain.calorieAdjustment, 300);
    });
  });
}

