// Implementierung für Android (Health Connect) und iOS (HealthKit)
import 'package:health/health.dart';
import 'package:dietry/services/app_logger.dart';
import '../models/physical_activity.dart';
import '../models/user_body_data.dart';

final _health = Health();

const _activityTypes = [
  HealthDataType.WORKOUT,
  HealthDataType.STEPS,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  // Required by the health plugin's WORKOUT handler to enrich exercise sessions
  // with distance and calorie totals. Without these, reading any WORKOUT record
  // fails with "Caller requires one of the permissions for record type 7".
  HealthDataType.DISTANCE_DELTA,
  HealthDataType.TOTAL_CALORIES_BURNED,
];

const _bodyTypes = [
  HealthDataType.WEIGHT,
  HealthDataType.HEIGHT,
  HealthDataType.BODY_FAT_PERCENTAGE,
];

Future<bool> requestHealthPermissions() async {
  try {
    await _health.configure();
    final granted = await _health.requestAuthorization(
      [..._activityTypes, ..._bodyTypes],
      permissions: [
        ..._activityTypes.map((_) => HealthDataAccess.READ),
        ..._bodyTypes.map((_) => HealthDataAccess.READ),
      ],
    );

    if (granted) {
      appLogger.i('✅ Health Connect Berechtigungen gewährt');
      // Verify permissions actually work by checking one data type
      try {
        final now = DateTime.now();
        final test = await _health.getHealthDataFromTypes(
          types: [HealthDataType.STEPS],
          startTime: now.subtract(const Duration(hours: 1)),
          endTime: now,
        );
        appLogger.i('✅ Berechtigungen funktionieren: ${test.length} Datenpunkte abgerufen');
      } catch (e) {
        appLogger.w('⚠️ Berechtigungen gewährt aber Abfrage fehlgeschlagen: $e');
        appLogger.i('💡 Bitte öffne Health Connect > Einstellungen > Berechtigungen und aktiviere Dietry manuell');
        return false;
      }
    }

    return granted;
  } catch (e) {
    appLogger.e('❌ Health Connect Berechtigungen fehlgeschlagen: $e');
    return false;
  }
}

Future<List<PhysicalActivity>> fetchHealthActivities({
  required DateTime start,
  required DateTime end,
}) async {
  final result = <PhysicalActivity>[];

  // Query each type separately so one permission error doesn't block all data

  // Structured workouts (WORKOUT type) — exercise sessions like walks, runs, etc.
  try {
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: start,
      endTime: end,
    );
    appLogger.i('🏋️ WORKOUT query returned ${data.length} records');

    for (final d in data) {
      try {
        final value = d.value as WorkoutHealthValue;
        result.add(PhysicalActivity(
          activityType: _mapWorkoutType(value.workoutActivityType),
          activityName: _workoutTypeName(value.workoutActivityType),
          startTime: d.dateFrom,
          endTime: d.dateTo,
          durationMinutes: d.dateTo.difference(d.dateFrom).inMinutes,
          caloriesBurned: value.totalEnergyBurned?.toDouble(),
          distanceKm: value.totalDistance != null
              ? value.totalDistance! / 1000.0  // m → km
              : null,
          source: DataSource.healthConnect,
          healthConnectRecordId: d.sourceId,
        ));
      } catch (e) {
        appLogger.w('⚠️ Failed to parse a WORKOUT record (value type=${d.value.runtimeType}): $e');
      }
    }
  } catch (e) {
    appLogger.w('⚠️ WORKOUT query failed: $e');
  }

  return result;
}

/// Maps a Health Connect workout type to our internal [ActivityType].
/// Anything we don't have a dedicated bucket for falls back to [ActivityType.other].
ActivityType _mapWorkoutType(HealthWorkoutActivityType type) {
  switch (type) {
    case HealthWorkoutActivityType.WALKING:
    case HealthWorkoutActivityType.WALKING_TREADMILL:
    case HealthWorkoutActivityType.WHEELCHAIR_WALK_PACE:
      return ActivityType.walking;
    case HealthWorkoutActivityType.RUNNING:
    case HealthWorkoutActivityType.RUNNING_TREADMILL:
    case HealthWorkoutActivityType.WHEELCHAIR_RUN_PACE:
      return ActivityType.running;
    case HealthWorkoutActivityType.BIKING:
    case HealthWorkoutActivityType.BIKING_STATIONARY:
      return ActivityType.cycling;
    case HealthWorkoutActivityType.SWIMMING:
    case HealthWorkoutActivityType.SWIMMING_OPEN_WATER:
    case HealthWorkoutActivityType.SWIMMING_POOL:
      return ActivityType.swimming;
    case HealthWorkoutActivityType.HIKING:
      return ActivityType.hiking;
    case HealthWorkoutActivityType.YOGA:
      return ActivityType.yoga;
    case HealthWorkoutActivityType.PILATES:
      return ActivityType.pilates;
    case HealthWorkoutActivityType.DANCING:
    case HealthWorkoutActivityType.SOCIAL_DANCE:
      return ActivityType.dancing;
    case HealthWorkoutActivityType.WEIGHTLIFTING:
    case HealthWorkoutActivityType.STRENGTH_TRAINING:
    case HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING:
    case HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING:
      return ActivityType.weightTraining;
    case HealthWorkoutActivityType.CALISTHENICS:
      return ActivityType.bodyweight;
    case HealthWorkoutActivityType.AMERICAN_FOOTBALL:
    case HealthWorkoutActivityType.AUSTRALIAN_FOOTBALL:
    case HealthWorkoutActivityType.SOCCER:
      return ActivityType.football;
    case HealthWorkoutActivityType.BASKETBALL:
      return ActivityType.basketball;
    case HealthWorkoutActivityType.TENNIS:
      return ActivityType.tennis;
    default:
      return ActivityType.other;
  }
}

Future<List<UserBodyMeasurement>> fetchHealthBodyMeasurements({
  required DateTime start,
  required DateTime end,
}) async {
  try {
    final data = await _health.getHealthDataFromTypes(
      types: _bodyTypes,
      startTime: start,
      endTime: end,
    );

    // Gruppiere nach Tag, nimm jeweils den neuesten Wert pro Typ
    final Map<String, Map<HealthDataType, double>> byDay = {};

    for (final d in data) {
      final day = d.dateFrom.toIso8601String().substring(0, 10);
      byDay.putIfAbsent(day, () => {});
      byDay[day]![d.type] = (d.value as NumericHealthValue).numericValue.toDouble();
    }

    return byDay.entries
        .where((e) => e.value.containsKey(HealthDataType.WEIGHT))
        .map((entry) {
          final values = entry.value;
          return UserBodyMeasurement(
            weight: values[HealthDataType.WEIGHT]!,
            bodyFatPercentage: values[HealthDataType.BODY_FAT_PERCENTAGE],
            measuredAt: DateTime.parse(entry.key),
          );
        })
        .toList();
  } catch (e) {
    appLogger.e('❌ Health Connect Körperdaten-Import fehlgeschlagen: $e');
    return [];
  }
}

/// Übersetzt HealthWorkoutActivityType in einen lesbaren Namen.
String _workoutTypeName(HealthWorkoutActivityType type) {
  final name = type.name
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');
  return name;
}
