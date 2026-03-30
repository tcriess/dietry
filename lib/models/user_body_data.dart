/// Zeitbasierte Körpermessungen (weight, body_fat, etc.)
/// Veränderlich - kann regelmäßig getrackt werden
class UserBodyMeasurement {
  final String? id;
  final double weight;  // kg
  final double? bodyFatPercentage;  // %
  final double? muscleMassKg;  // kg
  final double? waistCm;  // cm
  final DateTime measuredAt;
  final String? notes;
  
  UserBodyMeasurement({
    this.id,
    required this.weight,
    this.bodyFatPercentage,
    this.muscleMassKg,
    this.waistCm,
    required this.measuredAt,
    this.notes,
  });
  
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'weight': weight,
    if (bodyFatPercentage != null) 'body_fat_percentage': bodyFatPercentage,
    if (muscleMassKg != null) 'muscle_mass_kg': muscleMassKg,
    if (waistCm != null) 'waist_cm': waistCm,
    'measured_at': measuredAt.toIso8601String().split('T')[0],
    if (notes != null) 'notes': notes,
  };
  
  factory UserBodyMeasurement.fromJson(Map<String, dynamic> json) => UserBodyMeasurement(
    id: json['id'] as String?,
    weight: (json['weight'] as num).toDouble(),
    bodyFatPercentage: json['body_fat_percentage'] != null 
        ? (json['body_fat_percentage'] as num).toDouble() 
        : null,
    muscleMassKg: json['muscle_mass_kg'] != null 
        ? (json['muscle_mass_kg'] as num).toDouble() 
        : null,
    waistCm: json['waist_cm'] != null 
        ? (json['waist_cm'] as num).toDouble() 
        : null,
    measuredAt: DateTime.parse(json['measured_at']),
    notes: json['notes'] as String?,
  );
}

/// Statische Profildaten (height, birthdate, gender, etc.)
/// Unveränderlich oder selten änderbar
class UserProfile {
  final String? id;  // user_id
  final DateTime? birthdate;
  final double? height;  // cm
  final Gender? gender;
  final ActivityLevel? activityLevel;
  final WeightGoal? weightGoal;
  
  UserProfile({
    this.id,
    this.birthdate,
    this.height,
    this.gender,
    this.activityLevel,
    this.weightGoal,
  });
  
  /// Berechne Alter aus Geburtsdatum
  int? get age {
    if (birthdate == null) return null;
    final today = DateTime.now();
    int age = today.year - birthdate!.year;
    if (today.month < birthdate!.month || 
        (today.month == birthdate!.month && today.day < birthdate!.day)) {
      age--;
    }
    return age;
  }
  
  Map<String, dynamic> toJson() => {
    if (birthdate != null) 'birthdate': birthdate!.toIso8601String().split('T')[0],
    if (height != null) 'height': height,
    if (gender != null) 'gender': gender!.name,
    if (activityLevel != null) 'activity_level': activityLevel!.name,
    if (weightGoal != null) 'weight_goal': weightGoal!.name,
  };
  
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String?,
    birthdate: json['birthdate'] != null ? DateTime.parse(json['birthdate']) : null,
    height: json['height'] != null ? (json['height'] as num).toDouble() : null,
    gender: json['gender'] != null 
        ? Gender.values.firstWhere((e) => e.name == json['gender']) 
        : null,
    activityLevel: json['activity_level'] != null
        ? ActivityLevel.values.firstWhere((e) => e.name == json['activity_level'])
        : null,
    weightGoal: json['weight_goal'] != null
        ? WeightGoal.values.firstWhere((e) => e.name == json['weight_goal'])
        : null,
  );
}

/// Legacy: UserBodyData für Kalorien-Berechnungen
/// Kombiniert Profil + aktuelle Messung
class UserBodyData {
  final String? id;
  final double weight;  // kg (von Measurement)
  final double height;  // cm (von Profile)
  final Gender gender;  // (von Profile)
  final int age;  // (berechnet von Profile.birthdate)
  final ActivityLevel activityLevel;  // (von Profile)
  final WeightGoal weightGoal;  // (von Profile)
  final DateTime? measuredAt;
  
  // Berechnete Werte
  final double? bmr;
  final double? tdee;
  final double? targetCalories;

  UserBodyData({
    this.id,
    required this.weight,
    required this.height,
    required this.gender,
    required this.age,
    required this.activityLevel,
    required this.weightGoal,
    this.measuredAt,
    this.bmr,
    this.tdee,
    this.targetCalories,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'weight': weight,
    'height': height,
    'gender': gender.name,
    'age': age,
    'activity_level': activityLevel.name,
    'weight_goal': weightGoal.name,
    if (measuredAt != null) 'measured_at': measuredAt!.toIso8601String().split('T')[0],
    if (bmr != null) 'bmr': bmr,
    if (tdee != null) 'tdee': tdee,
    if (targetCalories != null) 'target_calories': targetCalories,
  };

  factory UserBodyData.fromJson(Map<String, dynamic> json) => UserBodyData(
    id: json['id'] as String?,
    weight: (json['weight'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    gender: Gender.values.firstWhere((e) => e.name == json['gender']),
    age: json['age'] as int,
    activityLevel: ActivityLevel.values.firstWhere((e) => e.name == json['activity_level']),
    weightGoal: WeightGoal.values.firstWhere((e) => e.name == json['weight_goal']),
    measuredAt: json['measured_at'] != null ? DateTime.parse(json['measured_at']) : null,
    bmr: json['bmr'] != null ? (json['bmr'] as num).toDouble() : null,
    tdee: json['tdee'] != null ? (json['tdee'] as num).toDouble() : null,
    targetCalories: json['target_calories'] != null ? (json['target_calories'] as num).toDouble() : null,
  );
}

enum Gender {
  male,
  female,
}

extension GenderExtension on Gender {
  String get displayName {
    switch (this) {
      case Gender.male:
        return 'Männlich';
      case Gender.female:
        return 'Weiblich';
    }
  }

  String localizedName(dynamic l) {
    switch (this) {
      case Gender.male:
        return l.genderMale as String;
      case Gender.female:
        return l.genderFemale as String;
    }
  }
}

enum ActivityLevel {
  sedentary,      // Wenig/keine Bewegung
  light,          // Leichte Aktivität (1-3 Tage/Woche)
  moderate,       // Moderate Aktivität (3-5 Tage/Woche)
  active,         // Aktiv (6-7 Tage/Woche)
  veryActive,     // Sehr aktiv (2x täglich)
}

extension ActivityLevelExtension on ActivityLevel {
  String get displayName {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Wenig Bewegung (Bürojob)';
      case ActivityLevel.light:
        return 'Leicht aktiv (1-3x/Woche Sport)';
      case ActivityLevel.moderate:
        return 'Moderat aktiv (3-5x/Woche Sport)';
      case ActivityLevel.active:
        return 'Sehr aktiv (6-7x/Woche Sport)';
      case ActivityLevel.veryActive:
        return 'Extrem aktiv (2x täglich Training)';
    }
  }

  String localizedName(dynamic l) {
    switch (this) {
      case ActivityLevel.sedentary:
        return l.activityLevelSedentary as String;
      case ActivityLevel.light:
        return l.activityLevelLight as String;
      case ActivityLevel.moderate:
        return l.activityLevelModerate as String;
      case ActivityLevel.active:
        return l.activityLevelActive as String;
      case ActivityLevel.veryActive:
        return l.activityLevelVeryActive as String;
    }
  }

  double get multiplier {
    switch (this) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.light:
        return 1.375;
      case ActivityLevel.moderate:
        return 1.55;
      case ActivityLevel.active:
        return 1.725;
      case ActivityLevel.veryActive:
        return 1.9;
    }
  }
}

enum WeightGoal {
  lose,           // Abnehmen (ca. 0.5kg/Woche)
  maintain,       // Gewicht halten
  gain,           // Zunehmen (Muskelaufbau)
}

extension WeightGoalExtension on WeightGoal {
  String get displayName {
    switch (this) {
      case WeightGoal.lose:
        return 'Abnehmen (0.5 kg/Woche)';
      case WeightGoal.maintain:
        return 'Gewicht halten';
      case WeightGoal.gain:
        return 'Zunehmen (Muskelaufbau)';
    }
  }

  String localizedName(dynamic l) {
    switch (this) {
      case WeightGoal.lose:
        return l.weightGoalLose as String;
      case WeightGoal.maintain:
        return l.weightGoalMaintain as String;
      case WeightGoal.gain:
        return l.weightGoalGain as String;
    }
  }

  int get calorieAdjustment {
    switch (this) {
      case WeightGoal.lose:
        return -500;  // 500 kcal Defizit pro Tag
      case WeightGoal.maintain:
        return 0;
      case WeightGoal.gain:
        return 300;   // 300 kcal Surplus
    }
  }
}

