import 'package:flutter/material.dart';

/// Physische Aktivität für Tracking und Health Connect Integration
class PhysicalActivity {
  final String? id;
  final ActivityType activityType;
  final String? activityId;  // Neu: Referenz zu activity_database
  final String? activityName;  // Neu: Name (aus DB oder manuell)
  final DateTime startTime;
  final DateTime endTime;
  final int? durationMinutes; // Berechnet oder manuell
  final double? caloriesBurned; // Optional: Geschätzt oder von Health Connect
  final double? distanceKm; // Optional: Für Laufen, Radfahren, etc.
  final int? steps; // Optional: Für Gehen/Laufen
  final double? avgHeartRate; // Optional: Von Health Connect
  final String? notes; // Notizen
  final DataSource source; // Manuell oder Health Connect
  final String? healthConnectRecordId; // ID von Health Connect für Sync
  final String? gearId; // Optional: Referenz zu gear (Laufschuhe, Rad, …)

  PhysicalActivity({
    this.id,
    this.activityType = ActivityType.other,
    this.activityId,
    this.activityName,
    required this.startTime,
    required this.endTime,
    this.durationMinutes,
    this.caloriesBurned,
    this.distanceKm,
    this.steps,
    this.avgHeartRate,
    this.notes,
    this.source = DataSource.manual,
    this.healthConnectRecordId,
    this.gearId,
  });
  
  /// Hole den Anzeige-Namen (activity_name hat Vorrang vor activityType)
  String get displayName => activityName ?? activityType.displayName;

  /// Berechnet Dauer in Minuten
  int get calculatedDuration => endTime.difference(startTime).inMinutes;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'activity_type': activityType.name,
    if (activityId != null) 'activity_id': activityId,
    if (activityName != null) 'activity_name': activityName,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'duration_minutes': durationMinutes ?? calculatedDuration,
    if (caloriesBurned != null) 'calories_burned': caloriesBurned,
    if (distanceKm != null) 'distance_km': distanceKm,
    if (steps != null) 'steps': steps,
    if (avgHeartRate != null) 'avg_heart_rate': avgHeartRate,
    if (notes != null) 'notes': notes,
    'source': source.name,
    if (healthConnectRecordId != null) 'health_connect_record_id': healthConnectRecordId,
    // Emitted even when null, unlike the fields above: updateActivity PATCHes
    // the full row, so an omitted gear_id could never be cleared once set.
    'gear_id': gearId,
  };

  factory PhysicalActivity.fromJson(Map<String, dynamic> json) => PhysicalActivity(
    id: json['id'] as String?,
    activityType: ActivityType.values.firstWhere(
      (e) => e.name == json['activity_type'],
      orElse: () => ActivityType.other,  // Fallback für Custom Activities
    ),
    activityId: json['activity_id'] as String?,
    activityName: json['activity_name'] as String?,
    startTime: DateTime.parse(json['start_time']),
    endTime: DateTime.parse(json['end_time']),
    durationMinutes: json['duration_minutes'] as int?,
    caloriesBurned: json['calories_burned'] != null ? (json['calories_burned'] as num).toDouble() : null,
    distanceKm: json['distance_km'] != null ? (json['distance_km'] as num).toDouble() : null,
    steps: json['steps'] as int?,
    avgHeartRate: json['avg_heart_rate'] != null ? (json['avg_heart_rate'] as num).toDouble() : null,
    notes: json['notes'] as String?,
    source: DataSource.values.firstWhere(
      (e) => e.name == json['source'],
      orElse: () => DataSource.manual,
    ),
    healthConnectRecordId: json['health_connect_record_id'] as String?,
    gearId: json['gear_id'] as String?,
  );

  /// Returns a copy with the given fields replaced. Used e.g. when moving an
  /// entry to another day/meal (re-dating [startTime]/[endTime] while keeping
  /// [id] and [healthConnectRecordId]). To duplicate an activity, construct a
  /// fresh [PhysicalActivity] instead so `id`/`healthConnectRecordId` can be
  /// cleared (copyWith can't set a field back to null).
  PhysicalActivity copyWith({
    String? id,
    ActivityType? activityType,
    String? activityId,
    String? activityName,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    double? caloriesBurned,
    double? distanceKm,
    int? steps,
    double? avgHeartRate,
    String? notes,
    DataSource? source,
    String? healthConnectRecordId,
    String? gearId,
    bool clearGearId = false,
  }) {
    return PhysicalActivity(
      id: id ?? this.id,
      activityType: activityType ?? this.activityType,
      activityId: activityId ?? this.activityId,
      activityName: activityName ?? this.activityName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      distanceKm: distanceKm ?? this.distanceKm,
      steps: steps ?? this.steps,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      healthConnectRecordId:
          healthConnectRecordId ?? this.healthConnectRecordId,
      gearId: clearGearId ? null : (gearId ?? this.gearId),
    );
  }
}

/// Aktivitätstypen (kompatibel mit Health Connect)
enum ActivityType {
  // Cardio
  walking,
  running,
  cycling,
  swimming,
  
  // Kraft
  weightTraining,
  bodyweight,
  
  // Sport
  football,
  basketball,
  tennis,
  
  // Fitness
  yoga,
  pilates,
  dancing,
  
  // Sonstiges
  hiking,
  other,
}

extension ActivityTypeExtension on ActivityType {
  String get displayName {
    switch (this) {
      case ActivityType.walking:
        return 'Gehen';
      case ActivityType.running:
        return 'Laufen';
      case ActivityType.cycling:
        return 'Radfahren';
      case ActivityType.swimming:
        return 'Schwimmen';
      case ActivityType.weightTraining:
        return 'Krafttraining';
      case ActivityType.bodyweight:
        return 'Bodyweight-Training';
      case ActivityType.football:
        return 'Fußball';
      case ActivityType.basketball:
        return 'Basketball';
      case ActivityType.tennis:
        return 'Tennis';
      case ActivityType.yoga:
        return 'Yoga';
      case ActivityType.pilates:
        return 'Pilates';
      case ActivityType.dancing:
        return 'Tanzen';
      case ActivityType.hiking:
        return 'Wandern';
      case ActivityType.other:
        return 'Sonstiges';
    }
  }

  /// Candidate `activity_database.name` values (DE/EN/ES) used to auto-link
  /// this activity type to a row in the activity database — e.g. when
  /// importing workouts from Health Connect. Listed in preference order;
  /// first case-insensitive name match wins. The DE entries match the
  /// German public seed; EN/ES variants forward-compat for localized seeds.
  List<String> get dbActivityCandidates {
    switch (this) {
      case ActivityType.walking:
        return const ['Gehen (normal)', 'Gehen', 'Walking', 'Caminar'];
      case ActivityType.running:
        return const ['Laufen (moderat)', 'Joggen (langsam)', 'Joggen', 'Laufen', 'Running', 'Correr'];
      case ActivityType.cycling:
        return const ['Radfahren (normal)', 'Radfahren', 'Cycling', 'Biking', 'Ciclismo'];
      case ActivityType.swimming:
        return const ['Schwimmen (normal)', 'Schwimmen', 'Swimming', 'Natación'];
      case ActivityType.hiking:
        return const ['Wandern', 'Hiking', 'Senderismo'];
      case ActivityType.yoga:
        return const ['Yoga'];
      case ActivityType.pilates:
        return const ['Pilates'];
      case ActivityType.dancing:
        return const ['Zumba', 'Aerobic', 'Dancing', 'Tanzen', 'Baile'];
      case ActivityType.weightTraining:
        return const [
          'Krafttraining (intensiv)', 'Krafttraining (leicht)', 'Krafttraining',
          'Weight training', 'Strength training', 'Pesas',
        ];
      case ActivityType.bodyweight:
        return const ['Bodyweight-Training', 'Bodyweight', 'Calisthenics', 'Calistenia'];
      case ActivityType.football:
        return const ['Fußball', 'Football', 'Soccer', 'Fútbol'];
      case ActivityType.basketball:
        return const ['Basketball', 'Baloncesto'];
      case ActivityType.tennis:
        return const ['Tennis', 'Tenis'];
      case ActivityType.other:
        return const [];
    }
  }

  /// Inverse of [dbActivityCandidates]: maps an `activity_database` row name
  /// back onto an [ActivityType]. Needed because the manual add form always
  /// writes `activity_type = 'other'` and keeps the real identity in
  /// `activity_id`/`activity_name` — so gear defaults, which are keyed by
  /// [ActivityType], have no type to match against otherwise.
  /// Returns null when no type claims the name.
  ///
  /// Falls back to the name with its intensity qualifier stripped, so the whole
  /// seeded family resolves — `dbActivityCandidates` lists 'Laufen (moderat)'
  /// but not 'Laufen (schnell)', and both should mean [ActivityType.running].
  static ActivityType? fromDbActivityName(String? name) {
    if (name == null) return null;
    final target = name.toLowerCase().trim();
    final base = target.replaceAll(RegExp(r'\s*\(.*\)$'), '').trim();

    for (final probe in [target, if (base != target) base]) {
      for (final type in ActivityType.values) {
        for (final candidate in type.dbActivityCandidates) {
          final c = candidate.toLowerCase();
          if (c == probe) return type;
          if (c.replaceAll(RegExp(r'\s*\(.*\)$'), '').trim() == probe) {
            return type;
          }
        }
      }
    }
    return null;
  }

  IconData get icon {
    switch (this) {
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.swimming:
        return Icons.pool;
      case ActivityType.weightTraining:
        return Icons.fitness_center;
      case ActivityType.bodyweight:
        return Icons.self_improvement;
      case ActivityType.football:
      case ActivityType.basketball:
      case ActivityType.tennis:
        return Icons.sports_soccer;
      case ActivityType.yoga:
      case ActivityType.pilates:
        return Icons.self_improvement;
      case ActivityType.dancing:
        return Icons.music_note;
      case ActivityType.hiking:
        return Icons.terrain;
      case ActivityType.other:
        return Icons.sports;
    }
  }

  /// Geschätzte MET-Werte (Metabolic Equivalent of Task)
  /// Für Kalorien-Schätzung wenn keine echten Daten verfügbar
  double get metValue {
    switch (this) {
      case ActivityType.walking:
        return 3.5; // Moderate Gehgeschwindigkeit
      case ActivityType.running:
        return 8.0; // Moderate Laufgeschwindigkeit
      case ActivityType.cycling:
        return 7.5; // Moderate Geschwindigkeit
      case ActivityType.swimming:
        return 6.0;
      case ActivityType.weightTraining:
        return 5.0;
      case ActivityType.bodyweight:
        return 4.0;
      case ActivityType.football:
        return 7.0;
      case ActivityType.basketball:
        return 6.5;
      case ActivityType.tennis:
        return 7.0;
      case ActivityType.yoga:
        return 2.5;
      case ActivityType.pilates:
        return 3.0;
      case ActivityType.dancing:
        return 4.5;
      case ActivityType.hiking:
        return 6.0;
      case ActivityType.other:
        return 4.0;
    }
  }
  
  /// Farbe für UI-Darstellung
  Color get color {
    switch (this) {
      case ActivityType.walking:
      case ActivityType.running:
      case ActivityType.hiking:
        return Colors.green;
      case ActivityType.cycling:
        return Colors.blue;
      case ActivityType.swimming:
        return Colors.cyan;
      case ActivityType.weightTraining:
      case ActivityType.bodyweight:
        return Colors.orange;
      case ActivityType.football:
      case ActivityType.basketball:
      case ActivityType.tennis:
        return Colors.red;
      case ActivityType.yoga:
      case ActivityType.pilates:
        return Colors.purple;
      case ActivityType.dancing:
        return Colors.pink;
      case ActivityType.other:
        return Colors.grey;
    }
  }
  
  /// Hat diese Aktivität eine Distanz-Komponente?
  bool get hasDistance {
    switch (this) {
      case ActivityType.walking:
      case ActivityType.running:
      case ActivityType.cycling:
      case ActivityType.swimming:
      case ActivityType.hiking:
        return true;
      default:
        return false;
    }
  }
}

/// Datenquelle für Aktivitäten
enum DataSource {
  manual,        // Manuell vom User eingegeben
  healthConnect, // Von Health Connect synchronisiert
  imported,      // Importiert von anderer App
}

extension DataSourceExtension on DataSource {
  String get displayName {
    switch (this) {
      case DataSource.manual:
        return 'Manuell';
      case DataSource.healthConnect:
        return 'Health Connect';
      case DataSource.imported:
        return 'Importiert';
    }
  }

  IconData get icon {
    switch (this) {
      case DataSource.manual:
        return Icons.edit;
      case DataSource.healthConnect:
        return Icons.health_and_safety;
      case DataSource.imported:
        return Icons.download;
    }
  }
}

/// Hilfsfunktionen für Kalorien-Berechnung
class ActivityCalorieCalculator {
  /// Berechnet verbrannte Kalorien basierend auf MET-Wert
  /// 
  /// Formel: Kalorien = MET × Gewicht (kg) × Dauer (Stunden)
  /// 
  /// Beispiel:
  /// - Laufen (MET=8) für 30 Min bei 70kg
  /// - Kalorien = 8 × 70 × 0.5 = 280 kcal
  static double calculateCalories({
    required ActivityType activityType,
    required int durationMinutes,
    required double weightKg,
  }) {
    final met = activityType.metValue;
    final hours = durationMinutes / 60.0;
    return met * weightKg * hours;
  }

  /// Schätzt durchschnittliche Herzfrequenz basierend auf Aktivitätstyp
  static double estimateAvgHeartRate({
    required ActivityType activityType,
    required int age,
  }) {
    final maxHeartRate = 220 - age;
    
    // Prozentsatz der max. Herzfrequenz je nach Aktivität
    double percentage;
    switch (activityType) {
      case ActivityType.walking:
        percentage = 0.5; // 50% von max
      case ActivityType.running:
        percentage = 0.75; // 75% von max
      case ActivityType.cycling:
        percentage = 0.7;
      case ActivityType.swimming:
        percentage = 0.7;
      case ActivityType.weightTraining:
        percentage = 0.65;
      case ActivityType.yoga:
        percentage = 0.4;
      default:
        percentage = 0.6;
    }
    
    return maxHeartRate * percentage;
  }
}

