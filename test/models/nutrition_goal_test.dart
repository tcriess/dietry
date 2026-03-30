import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/models.dart';

void main() {
  group('NutritionGoal Model', () {
    test('fromJson sollte valides Objekt erstellen', () {
      final json = {
        'id': 'goal-123',
        'user_id': 'user-456',
        'calories': 2000.0,
        'protein': 150.0,
        'fat': 65.0,
        'carbs': 200.0,
        'valid_from': '2026-03-24',
      };

      final goal = NutritionGoal.fromJson(json);

      expect(goal.id, 'goal-123');
      expect(goal.userId, 'user-456');
      expect(goal.calories, 2000.0);
      expect(goal.protein, 150.0);
      expect(goal.fat, 65.0);
      expect(goal.carbs, 200.0);
      expect(goal.validFrom, DateTime(2026, 3, 24));
    });

    test('toJson sollte korrektes JSON erstellen', () {
      final goal = NutritionGoal(
        id: 'goal-123',
        userId: 'user-456',
        calories: 2200.0,
        protein: 165.0,
        fat: 70.0,
        carbs: 220.0,
        validFrom: DateTime(2026, 3, 24),
      );

      final json = goal.toJson();

      expect(json['id'], 'goal-123');
      expect(json['user_id'], 'user-456');
      expect(json['calories'], 2200.0);
      expect(json['protein'], 165.0);
      expect(json['fat'], 70.0);
      expect(json['carbs'], 220.0);
      expect(json['valid_from'], '2026-03-24');
    });

    test('NutritionGoal mit minimalen Werten sollte funktionieren', () {
      final goal = NutritionGoal(
        calories: 2000.0,
        protein: 150.0,
        fat: 65.0,
        carbs: 200.0,
      );

      expect(goal.id, isNull);
      expect(goal.userId, isNull);
      expect(goal.validFrom, isNull);
      expect(goal.calories, 2000.0);
    });

    test('toJson sollte null-Werte auslassen', () {
      final goal = NutritionGoal(
        calories: 2000.0,
        protein: 150.0,
        fat: 65.0,
        carbs: 200.0,
      );

      final json = goal.toJson();

      expect(json.containsKey('id'), false);
      expect(json.containsKey('user_id'), false);
      expect(json.containsKey('valid_from'), false);
      expect(json['calories'], 2000.0);
    });

    test('Makro-Werte sollten korrekt gespeichert werden', () {
      final goal = NutritionGoal(
        calories: 2500.0,
        protein: 180.5,
        fat: 72.3,
        carbs: 245.8,
        validFrom: DateTime(2026, 3, 20),
      );

      expect(goal.protein, 180.5);
      expect(goal.fat, 72.3);
      expect(goal.carbs, 245.8);
    });
  });
}

