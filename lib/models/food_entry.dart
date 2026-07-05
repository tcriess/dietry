/// Model für tägliche Food-Einträge (food_entries Tabelle)
/// 
/// Repräsentiert eine konkrete Mahlzeit/Portion die ein User gegessen hat.
class FoodEntry {
  final String id;
  final String userId;
  final String? foodId;  // Referenz zu food_database (optional)
  final String? mealTemplateId;  // Referenz zu meal_templates (optional, Cloud Edition)

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
  // `sodium` ist der DB-Spaltenname; gespeichert wird SALZ in Gramm (NaCl).
  final double? sodium;
  final double? saturatedFat;

  // Notizen
  final String? notes;

  // Flüssigkeitsmarkierung - wenn true, zählt zur Wasseraufnahme
  final bool isLiquid;
  // For liquid foods: the ml amount (null for non-liquid entries)
  final double? amountMl;

  // Meal vs food: if true, nutrition values are totals for the whole entry (meal)
  // if false, nutrition values are totals for the specified amount (food)
  final bool isMeal;

  // How uncertain this entry's nutrition is (see [EstimateLevel]). Drives the
  // daily uncertainty band; does NOT change the nutrition means. Default: exact.
  final EstimateLevel estimateLevel;

  // Metadaten
  final DateTime createdAt;
  final DateTime updatedAt;
  
  FoodEntry({
    required this.id,
    required this.userId,
    this.foodId,
    this.mealTemplateId,
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
    this.saturatedFat,
    this.notes,
    this.isLiquid = false,
    this.amountMl,
    this.isMeal = false,
    this.estimateLevel = EstimateLevel.none,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Standard deviation (σ) of a nutrient total for this entry, given its
  /// estimate level. σ = value × CV(level). Used to build the daily band
  /// (variances add: σ_day = √Σσ²).
  double sigmaOf(double value) => value * estimateLevel.cv;

  double get caloriesSigma => sigmaOf(calories);
  double get proteinSigma => sigmaOf(protein);
  double get fatSigma => sigmaOf(fat);
  double get carbsSigma => sigmaOf(carbs);
  
  /// Erstelle FoodEntry aus JSON (Datenbank-Response)
  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    return FoodEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      foodId: json['food_id'] as String?,
      mealTemplateId: json['meal_template_id'] as String?,
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
      saturatedFat: json['saturated_fat'] != null ? (json['saturated_fat'] as num).toDouble() : null,
      notes: json['notes'] as String?,
      isLiquid: json['is_liquid'] as bool? ?? false,
      amountMl: json['amount_ml'] != null ? (json['amount_ml'] as num).toDouble() : null,
      isMeal: json['is_meal'] as bool? ?? false,
      estimateLevel: EstimateLevel.fromJson(json['estimate_level'] as String?),
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
      if (mealTemplateId != null) 'meal_template_id': mealTemplateId,
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
      if (saturatedFat != null) 'saturated_fat': saturatedFat,
      if (notes != null) 'notes': notes,
      'is_liquid': isLiquid,
      if (amountMl != null) 'amount_ml': amountMl,
      'is_meal': isMeal,
      'estimate_level': estimateLevel.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Erstelle Kopie mit geänderten Werten
  FoodEntry copyWith({
    String? id,
    String? userId,
    String? foodId,
    String? mealTemplateId,
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
    double? saturatedFat,
    String? notes,
    bool? isLiquid,
    double? amountMl,
    bool? isMeal,
    EstimateLevel? estimateLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      foodId: foodId ?? this.foodId,
      mealTemplateId: mealTemplateId ?? this.mealTemplateId,
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
      saturatedFat: saturatedFat ?? this.saturatedFat,
      notes: notes ?? this.notes,
      isLiquid: isLiquid ?? this.isLiquid,
      amountMl: amountMl ?? this.amountMl,
      isMeal: isMeal ?? this.isMeal,
      estimateLevel: estimateLevel ?? this.estimateLevel,
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

/// How uncertain a food entry's nutrition is.
///
/// Each level maps to a coefficient of variation (CV = σ/μ) that is applied to
/// every nutrient of the entry. The nutrition *means* are never changed — this
/// only feeds the daily uncertainty band, which aggregates by adding variances
/// (σ_day = √Σσ²). `none` = weighed/packaged (exact); higher = rougher guess.
enum EstimateLevel {
  none,
  low,
  medium,
  high;

  String toJson() => name;

  /// Tolerant parse: unknown/missing → [none] (backward-compatible default).
  static EstimateLevel fromJson(String? value) =>
      EstimateLevel.values.firstWhere(
        (e) => e.name == value,
        orElse: () => EstimateLevel.none,
      );

  /// Coefficient of variation (σ/μ) for this level. Tunable; chosen so a "high"
  /// guess is ~±45%. Amount error dominates and scales all nutrients together,
  /// so one CV per entry (applied proportionally) is a principled first cut.
  double get cv {
    switch (this) {
      case EstimateLevel.none:
        return 0.0;
      case EstimateLevel.low:
        return 0.10;
      case EstimateLevel.medium:
        return 0.25;
      case EstimateLevel.high:
        return 0.45;
    }
  }

  String localizedName(dynamic l) {
    switch (this) {
      case EstimateLevel.none:
        return l.estimateNone as String;
      case EstimateLevel.low:
        return l.estimateLow as String;
      case EstimateLevel.medium:
        return l.estimateMedium as String;
      case EstimateLevel.high:
        return l.estimateHigh as String;
    }
  }
}

