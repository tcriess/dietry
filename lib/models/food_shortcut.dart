import 'dart:convert';

/// Ein gespeicherter Schnell-Eintrag für die Quick-Add-Funktion.
///
/// Kapselt alle Daten die nötig sind um einen Food-Entry ohne API-Aufruf
/// sofort hinzuzufügen. Wird in SharedPreferences als JSON gespeichert.
class FoodShortcut {
  final String id;
  final String label;
  final String? foodId; // Referenz auf food_database (optional)
  final String mealType; // 'breakfast' | 'lunch' | 'dinner' | 'snack'
  final double amount;
  final String unit;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;

  const FoodShortcut({
    required this.id,
    required this.label,
    this.foodId,
    required this.mealType,
    required this.amount,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
  });

  factory FoodShortcut.fromJson(Map<String, dynamic> json) => FoodShortcut(
        id: json['id'] as String,
        label: json['label'] as String,
        foodId: json['food_id'] as String?,
        mealType: json['meal_type'] as String,
        amount: (json['amount'] as num).toDouble(),
        unit: json['unit'] as String,
        calories: (json['calories'] as num).toDouble(),
        protein: (json['protein'] as num).toDouble(),
        fat: (json['fat'] as num).toDouble(),
        carbs: (json['carbs'] as num).toDouble(),
        fiber: json['fiber'] != null ? (json['fiber'] as num).toDouble() : null,
        sugar: json['sugar'] != null ? (json['sugar'] as num).toDouble() : null,
        sodium: json['sodium'] != null ? (json['sodium'] as num).toDouble() : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (foodId != null) 'food_id': foodId,
        'meal_type': mealType,
        'amount': amount,
        'unit': unit,
        'calories': calories,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        if (fiber != null) 'fiber': fiber,
        if (sugar != null) 'sugar': sugar,
        if (sodium != null) 'sodium': sodium,
      };

  static FoodShortcut fromJsonString(String s) =>
      FoodShortcut.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());
}
