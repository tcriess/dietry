/// Model für tägliche Food-Einträge (food_entries Tabelle)
/// 
/// Repräsentiert eine konkrete Mahlzeit/Portion die ein User gegessen hat.
class FoodEntry {
  final String id;
  final String userId;
  final String? foodId;  // Referenz zu food_database (optional)
  
  // Datum & Mahlzeit
  final DateTime entryDate;
  final MealType mealType;
  
  // Name & Menge
  final String name;
  final double amount;
  final String unit;
  
  // Nährwerte (berechnet oder manuell)
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  
  // Optional
  final double? fiber;
  final double? sugar;
  final double? sodium;
  
  // Notizen
  final String? notes;
  
  // Metadaten
  final DateTime createdAt;
  final DateTime updatedAt;
  
  FoodEntry({
    required this.id,
    required this.userId,
    this.foodId,
    required this.entryDate,
    required this.mealType,
    required this.name,
    required this.amount,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  
  /// Erstelle FoodEntry aus JSON (Datenbank-Response)
  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    return FoodEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      foodId: json['food_id'] as String?,
      entryDate: DateTime.parse(json['entry_date'] as String),
      mealType: MealType.fromJson(json['meal_type'] as String),
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      carbs: (json['carbs'] as num).toDouble(),
      fiber: json['fiber'] != null ? (json['fiber'] as num).toDouble() : null,
      sugar: json['sugar'] != null ? (json['sugar'] as num).toDouble() : null,
      sodium: json['sodium'] != null ? (json['sodium'] as num).toDouble() : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
  
  /// Konvertiere FoodEntry zu JSON (für Datenbank-Insert/Update)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (foodId != null) 'food_id': foodId,
      'entry_date': entryDate.toIso8601String().split('T')[0],  // Nur Datum
      'meal_type': mealType.toJson(),
      'name': name,
      'amount': amount,
      'unit': unit,
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      if (fiber != null) 'fiber': fiber,
      if (sugar != null) 'sugar': sugar,
      if (sodium != null) 'sodium': sodium,
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Erstelle Kopie mit geänderten Werten
  FoodEntry copyWith({
    String? id,
    String? userId,
    String? foodId,
    DateTime? entryDate,
    MealType? mealType,
    String? name,
    double? amount,
    String? unit,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    double? fiber,
    double? sugar,
    double? sodium,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      foodId: foodId ?? this.foodId,
      entryDate: entryDate ?? this.entryDate,
      mealType: mealType ?? this.mealType,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      sodium: sodium ?? this.sodium,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  @override
  String toString() {
    return 'FoodEntry(id: $id, name: $name, amount: $amount$unit, calories: $calories kcal, date: $entryDate, meal: $mealType)';
  }
}

/// Meal Type Enum
enum MealType {
  breakfast,
  lunch,
  dinner,
  snack;
  
  String toJson() => name;
  
  static MealType fromJson(String value) {
    return MealType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MealType.snack,
    );
  }
  
  /// Lokalisierter Display-Name
  String get displayName {
    switch (this) {
      case MealType.breakfast:
        return 'Frühstück';
      case MealType.lunch:
        return 'Mittagessen';
      case MealType.dinner:
        return 'Abendessen';
      case MealType.snack:
        return 'Snack';
    }
  }
  
  /// Lokalisierter Name via AppLocalizations
  String localizedName(dynamic l) {
    switch (this) {
      case MealType.breakfast:
        return l.mealBreakfast as String;
      case MealType.lunch:
        return l.mealLunch as String;
      case MealType.dinner:
        return l.mealDinner as String;
      case MealType.snack:
        return l.mealSnack as String;
    }
  }

  /// Icon für UI
  String get icon {
    switch (this) {
      case MealType.breakfast:
        return '🌅';
      case MealType.lunch:
        return '☀️';
      case MealType.dinner:
        return '🌙';
      case MealType.snack:
        return '🍎';
    }
  }
}

