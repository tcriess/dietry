import 'package:flutter/material.dart';
import 'physical_activity.dart';

/// A piece of equipment a workout can be attributed to — a pair of running
/// shoes, a bike, … — so the user can see how much time and distance it has
/// accumulated. Mirrors the `gear` table (sql/34_gear.sql).
class Gear {
  final String? id;
  final String name;
  final GearCategory category;

  /// Auto-attach this gear to imported activities of this type (Health Connect
  /// sets a real [ActivityType]; the manual form derives one from the chosen
  /// activity-database row). `null` = never auto-attach.
  final ActivityType? defaultActivityType;

  /// Kilometres already on the item before tracking started.
  final double initialDistanceKm;

  /// Optional wear budget ("replace at 800 km"). `null` = no budget.
  final double? retireAtKm;

  final bool retired;
  final String? notes;

  const Gear({
    this.id,
    required this.name,
    this.category = GearCategory.shoes,
    this.defaultActivityType,
    this.initialDistanceKm = 0,
    this.retireAtKm,
    this.retired = false,
    this.notes,
  });

  /// `gear_id`, `default_activity_type`, `retire_at_km` and `notes` are emitted
  /// even when null: PATCH sends the full row, so omitting them would make it
  /// impossible to clear a value once set.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category.name,
        'default_activity_type': defaultActivityType?.name,
        'initial_distance_km': initialDistanceKm,
        'retire_at_km': retireAtKm,
        'retired': retired,
        'notes': notes,
      };

  factory Gear.fromJson(Map<String, dynamic> json) => Gear(
        id: json['id'] as String?,
        name: json['name'] as String,
        category: GearCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => GearCategory.other,
        ),
        defaultActivityType: json['default_activity_type'] == null
            ? null
            : ActivityType.values.firstWhere(
                (t) => t.name == json['default_activity_type'],
                orElse: () => ActivityType.other,
              ),
        initialDistanceKm:
            (json['initial_distance_km'] as num?)?.toDouble() ?? 0,
        retireAtKm: (json['retire_at_km'] as num?)?.toDouble(),
        // SQLite has no bool — it round-trips as 0/1.
        retired: json['retired'] == true || json['retired'] == 1,
        notes: json['notes'] as String?,
      );

  Gear copyWith({
    String? id,
    String? name,
    GearCategory? category,
    ActivityType? defaultActivityType,
    double? initialDistanceKm,
    double? retireAtKm,
    bool? retired,
    String? notes,
    bool clearDefaultActivityType = false,
    bool clearRetireAtKm = false,
  }) =>
      Gear(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        defaultActivityType: clearDefaultActivityType
            ? null
            : (defaultActivityType ?? this.defaultActivityType),
        initialDistanceKm: initialDistanceKm ?? this.initialDistanceKm,
        retireAtKm: clearRetireAtKm ? null : (retireAtKm ?? this.retireAtKm),
        retired: retired ?? this.retired,
        notes: notes ?? this.notes,
      );
}

/// Lifetime usage of one [Gear], aggregated over every activity it is attached
/// to. Distance already includes [Gear.initialDistanceKm].
class GearTotals {
  final String gearId;
  final double totalDistanceKm;
  final int totalMinutes;
  final int activityCount;
  final DateTime? lastUsed;

  const GearTotals({
    required this.gearId,
    this.totalDistanceKm = 0,
    this.totalMinutes = 0,
    this.activityCount = 0,
    this.lastUsed,
  });

  factory GearTotals.fromJson(Map<String, dynamic> json) => GearTotals(
        gearId: json['gear_id'] as String,
        totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0,
        totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
        activityCount: (json['activity_count'] as num?)?.toInt() ?? 0,
        lastUsed: json['last_used'] == null
            ? null
            : DateTime.parse(json['last_used'] as String),
      );

  /// Fraction of the wear budget used, or null when the gear has no budget.
  double? wearFraction(double? retireAtKm) {
    if (retireAtKm == null || retireAtKm <= 0) return null;
    return totalDistanceKm / retireAtKm;
  }
}

enum GearCategory { shoes, bike, other }

extension GearCategoryX on GearCategory {
  IconData get icon {
    switch (this) {
      case GearCategory.shoes:
        return Icons.directions_run;
      case GearCategory.bike:
        return Icons.directions_bike;
      case GearCategory.other:
        return Icons.fitness_center;
    }
  }
}
