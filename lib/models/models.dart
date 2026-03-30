// Model-Klassen für Dietry mit Datenbank-Integration

export 'user.dart';
export 'user_body_data.dart';
export 'cheat_day.dart';
export 'streak_record.dart';
export 'physical_activity.dart';
export 'tracking_method.dart';

import 'tracking_method.dart';
export 'food_item.dart';
export 'food_entry.dart';
export 'water_intake.dart';

// Legacy EstimateLevel (für alte FoodEntry-Implementierung)
enum EstimateLevel { 
  low, 
  medium, 
  high, 
  none;
  
  String toJson() => name;
  static EstimateLevel fromJson(String value) => EstimateLevel.values.firstWhere((e) => e.name == value);
}


class NutritionGoal {
  final String? id;
  final String? userId;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final DateTime? validFrom;
  final TrackingMethod? trackingMethod;
  final int? waterGoalMl;

  const NutritionGoal({
    this.id,
    this.userId,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.validFrom,
    this.trackingMethod,
    this.waterGoalMl,
  });

  factory NutritionGoal.fromJson(Map<String, dynamic> json) {
    final methodStr = json['tracking_method'] as String?;
    return NutritionGoal(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      carbs: (json['carbs'] as num).toDouble(),
      validFrom: json['valid_from'] != null
        ? DateTime.parse(json['valid_from'] as String)
        : null,
      trackingMethod: methodStr != null
        ? TrackingMethod.values.firstWhere(
            (e) => e.name == methodStr,
            orElse: () => TrackingMethod.tdeeHybrid,
          )
        : null,
      waterGoalMl: json['water_goal_ml'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (userId != null) 'user_id': userId,
    'calories': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    if (validFrom != null) 'valid_from': validFrom!.toIso8601String().split('T')[0],
    if (trackingMethod != null) 'tracking_method': trackingMethod!.name,
    if (waterGoalMl != null) 'water_goal_ml': waterGoalMl,
  };
}
