import 'food_portion.dart';
import 'tag.dart';

/// Model für Lebensmittel aus der food_database
///
/// Repräsentiert ein Lebensmittel mit Nährwerten pro 100g/100ml.
/// Kann public (für alle User) oder private (user-spezifisch) sein.
class FoodItem {
  final String id;
  final String? userId;  // NULL für public items
  final String name;
  
  // Nährwerte pro 100g/100ml (standardisiert)
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  
  // Optional
  final double? fiber;
  final double? sugar;
  final double? sodium;
  final double? saturatedFat;
  
  // Portionsgröße (Vorschlag)
  final double? servingSize;
  final String? servingUnit;

  // Benannte Portionsgrößen
  final List<FoodPortion> portions;
  
  // Kategorisierung
  final String? category;
  final String? brand;
  final String? barcode;
  
  // Public/Private
  final bool isPublic;
  final bool isApproved;  // TRUE = Admin hat Freigabe erteilt

  // Nutzer-Markierung
  final bool isFavourite;

  // Flüssigkeitsmarkierung - wenn true, Einheit standardmäßig ml, Menge zählt zur Wasseraufnahme
  final bool isLiquid;

  // Image support - true if an image exists in food_images table
  final bool hasImage;

  // Tags - user-specific; visible to all if set by food owner, else private
  final List<Tag> tags;

  // Metadaten
  final String? source;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  FoodItem({
    required this.id,
    this.userId,
    required this.name,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    this.saturatedFat,
    this.servingSize,
    this.servingUnit,
    this.portions = const [],
    this.category,
    this.brand,
    this.barcode,
    required this.isPublic,
    required this.isApproved,
    this.isFavourite = false,
    this.isLiquid = false,
    this.hasImage = false,
    this.tags = const [],
    this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  
  /// Erstelle FoodItem aus JSON (Datenbank-Response)
  factory FoodItem.fromJson(Map<String, dynamic> json) {
    // Safely parse required fields with null checks
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final createdAtRaw = json['created_at'] as String?;
    final updatedAtRaw = json['updated_at'] as String?;

    if (id == null || name == null || createdAtRaw == null || updatedAtRaw == null) {
      throw FormatException('Missing required fields in FoodItem.fromJson: '
          'id=$id, name=$name, created_at=$createdAtRaw, updated_at=$updatedAtRaw');
    }

    return FoodItem(
      id: id,
      userId: json['user_id'] as String?,
      name: name,
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      carbs: (json['carbs'] as num).toDouble(),
      fiber: json['fiber'] != null ? (json['fiber'] as num).toDouble() : null,
      sugar: json['sugar'] != null ? (json['sugar'] as num).toDouble() : null,
      sodium: json['sodium'] != null ? (json['sodium'] as num).toDouble() : null,
      saturatedFat: json['saturated_fat'] != null ? (json['saturated_fat'] as num).toDouble() : null,
      servingSize: json['serving_size'] != null ? (json['serving_size'] as num).toDouble() : null,
      servingUnit: _safeString(json['serving_unit']),
      portions: _parsePortions(json),
      category: _safeString(json['category']),
      brand: _safeString(json['brand']),
      barcode: _safeString(json['barcode']),
      isPublic: json['is_public'] as bool? ?? false,
      isApproved: json['is_approved'] as bool? ?? false,
      isFavourite: json['is_favourite'] as bool? ?? false,
      isLiquid: json['is_liquid'] as bool? ?? false,
      hasImage: json['has_image'] as bool? ?? false,
      tags: _parseTags(json['tags']),
      source: _safeString(json['source']),
      createdAt: DateTime.parse(createdAtRaw),
      updatedAt: DateTime.parse(updatedAtRaw),
    );
  }

  /// Safely cast dynamic value to String or null
  static String? _safeString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    return value.toString();
  }
  
  static List<FoodPortion> _parsePortions(Map<String, dynamic> json) {
    final raw = json['portions'];
    if (raw is List && raw.isNotEmpty) {
      final portions = <FoodPortion>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        try {
          portions.add(FoodPortion.fromJson(item));
        } catch (e) {
          // Skip invalid portions instead of crashing
          continue;
        }
      }
      return portions;
    }
    // Fallback: convert single serving_size/serving_unit to a portion
    final size = json['serving_size'];
    final unit = _safeString(json['serving_unit']);
    if (size != null && unit != null && unit != 'g' && unit != 'ml') {
      // Only create a named portion if unit is not g/ml (those are covered by defaults)
      try {
        return [FoodPortion(name: '1 Portion', amountG: (size as num).toDouble())];
      } catch (e) {
        return [];
      }
    }
    return [];
  }

  static List<Tag> _parseTags(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final tags = <Tag>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        try {
          tags.add(Tag.fromJson(item));
        } catch (e) {
          // Skip invalid tags instead of crashing
          continue;
        }
      }
      return tags;
    }
    return [];
  }

  /// Konvertiere FoodItem zu JSON (für Datenbank-Insert/Update)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      if (fiber != null) 'fiber': fiber,
      if (sugar != null) 'sugar': sugar,
      if (sodium != null) 'sodium': sodium,
      if (saturatedFat != null) 'saturated_fat': saturatedFat,
      if (servingSize != null) 'serving_size': servingSize,
      if (servingUnit != null) 'serving_unit': servingUnit,
      if (portions.isNotEmpty) 'portions': portions.map((p) => p.toJson()).toList(),
      if (category != null) 'category': category,
      if (brand != null) 'brand': brand,
      if (barcode != null) 'barcode': barcode,
      'is_public': isPublic,
      'is_approved': isApproved,
      'is_favourite': isFavourite,
      'is_liquid': isLiquid,
      'has_image': hasImage,
      if (source != null) 'source': source,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Berechne Nährwerte für eine bestimmte Menge
  /// 
  /// [amount] - Menge in g/ml
  /// Returns: Map mit berechneten Nährwerten
  Map<String, double> calculateNutrition(double amount) {
    final factor = amount / 100.0;
    
    return {
      'calories': calories * factor,
      'protein': protein * factor,
      'fat': fat * factor,
      'carbs': carbs * factor,
      if (fiber != null) 'fiber': fiber! * factor,
      if (sugar != null) 'sugar': sugar! * factor,
      if (sodium != null) 'sodium': sodium! * factor,
      if (saturatedFat != null) 'saturated_fat': saturatedFat! * factor,
    };
  }
  
  /// Erstelle Kopie mit geänderten Werten
  FoodItem copyWith({
    String? id,
    String? userId,
    String? name,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    double? fiber,
    double? sugar,
    double? sodium,
    double? saturatedFat,
    double? servingSize,
    String? servingUnit,
    List<FoodPortion>? portions,
    String? category,
    String? brand,
    String? barcode,
    bool? isPublic,
    bool? isApproved,
    bool? isFavourite,
    bool? isLiquid,
    bool? hasImage,
    List<Tag>? tags,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      sodium: sodium ?? this.sodium,
      saturatedFat: saturatedFat ?? this.saturatedFat,
      servingSize: servingSize ?? this.servingSize,
      servingUnit: servingUnit ?? this.servingUnit,
      portions: portions ?? this.portions,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      barcode: barcode ?? this.barcode,
      isPublic: isPublic ?? this.isPublic,
      isApproved: isApproved ?? this.isApproved,
      isFavourite: isFavourite ?? this.isFavourite,
      isLiquid: isLiquid ?? this.isLiquid,
      hasImage: hasImage ?? this.hasImage,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  @override
  String toString() {
    return 'FoodItem(id: $id, name: $name, calories: $calories, isPublic: $isPublic)';
  }
}

