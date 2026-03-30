/// Model für activity_database Tabelle
class ActivityItem {
  final String id;
  final String? userId;
  final String name;
  final double metValue;
  final String? category;
  final String? intensity;
  final String? description;
  final double? avgSpeedKmh;
  final bool isPublic;
  final bool isApproved;  // TRUE = Admin hat Freigabe erteilt
  final bool isFavourite;
  final String? source;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  const ActivityItem({
    required this.id,
    this.userId,
    required this.name,
    required this.metValue,
    this.category,
    this.intensity,
    this.description,
    this.avgSpeedKmh,
    required this.isPublic,
    required this.isApproved,
    this.isFavourite = false,
    this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      name: json['name'] as String,
      metValue: (json['met_value'] as num).toDouble(),
      category: json['category'] as String?,
      intensity: json['intensity'] as String?,
      description: json['description'] as String?,
      avgSpeedKmh: json['avg_speed_kmh'] != null 
          ? (json['avg_speed_kmh'] as num).toDouble() 
          : null,
      isPublic: json['is_public'] as bool,
      isApproved: json['is_approved'] as bool? ?? false,
      isFavourite: json['is_favourite'] as bool? ?? false,
      source: json['source'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'met_value': metValue,
      'category': category,
      'intensity': intensity,
      'description': description,
      'avg_speed_kmh': avgSpeedKmh,
      'is_public': isPublic,
      'is_approved': isApproved,
      'is_favourite': isFavourite,
      'source': source,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Berechne Kalorien für gegebene Dauer und Gewicht
  /// 
  /// Formel: Kalorien = MET × Gewicht(kg) × Dauer(h)
  /// 
  /// Beispiel: Joggen (MET=7) für 30min bei 80kg
  /// = 7 × 80 × 0.5 = 280 kcal
  double calculateCalories({
    required double weightKg,
    required int durationMinutes,
  }) {
    final durationHours = durationMinutes / 60.0;
    return metValue * weightKg * durationHours;
  }
  
  /// Schätze Distanz basierend auf Geschwindigkeit und Dauer
  /// 
  /// Nur für Aktivitäten mit avgSpeedKmh verfügbar
  double? estimateDistance(int durationMinutes) {
    if (avgSpeedKmh == null) return null;
    final durationHours = durationMinutes / 60.0;
    return avgSpeedKmh! * durationHours;
  }
  
  /// Intensity als lesbarer String
  String? get intensityDisplayName {
    switch (intensity) {
      case 'low':
        return 'Niedrig';
      case 'moderate':
        return 'Moderat';
      case 'high':
        return 'Hoch';
      case 'very_high':
        return 'Sehr Hoch';
      default:
        return null;
    }
  }
  
  /// Icon basierend auf Kategorie
  String get categoryIcon {
    switch (category) {
      case 'Ausdauer':
        return '🏃';
      case 'Kraft':
        return '💪';
      case 'Sport':
        return '⚽';
      case 'Fitness':
        return '🧘';
      case 'Alltag':
        return '🏠';
      default:
        return '🏃';
    }
  }
}

