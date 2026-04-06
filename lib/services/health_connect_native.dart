// Implementierung für Android (Health Connect) und iOS (HealthKit)
import 'package:health/health.dart';
import '../models/physical_activity.dart';
import '../models/user_body_data.dart';

final _health = Health();

const _activityTypes = [
  HealthDataType.WORKOUT,
  HealthDataType.STEPS,
  HealthDataType.ACTIVE_ENERGY_BURNED,
];

const _bodyTypes = [
  HealthDataType.WEIGHT,
  HealthDataType.HEIGHT,
  HealthDataType.BODY_FAT_PERCENTAGE,
];

Future<bool> requestHealthPermissions() async {
  try {
    await _health.configure();
    return await _health.requestAuthorization(
      [..._activityTypes, ..._bodyTypes],
      permissions: [
        ..._activityTypes.map((_) => HealthDataAccess.READ),
        ..._bodyTypes.map((_) => HealthDataAccess.READ),
      ],
    );
  } catch (e) {
    print('❌ Health Connect Berechtigungen fehlgeschlagen: $e');
    return false;
  }
}

Future<List<PhysicalActivity>> fetchHealthActivities({
  required DateTime start,
  required DateTime end,
}) async {
  try {
    final data = await _health.getHealthDataFromTypes(
      types: _activityTypes,
      startTime: start,
      endTime: end,
    );

    final result = <PhysicalActivity>[];

    // Structured workouts (WORKOUT type)
    final workouts = data.where((d) => d.type == HealthDataType.WORKOUT);
    result.addAll(workouts.map((d) {
      final value = d.value as WorkoutHealthValue;
      return PhysicalActivity(
        activityType: ActivityType.other,
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
      );
    }));

    // Simple active calorie burns (log entries without duration info)
    final activeCalories = data.where((d) => d.type == HealthDataType.ACTIVE_ENERGY_BURNED);
    result.addAll(activeCalories.map((d) {
      final value = (d.value as NumericHealthValue).numericValue;
      return PhysicalActivity(
        activityType: ActivityType.other,
        activityName: 'Active Calories',
        startTime: d.dateFrom,
        endTime: d.dateFrom,  // No duration data for simple burns
        durationMinutes: 0,
        caloriesBurned: value.toDouble(),
        distanceKm: null,
        source: DataSource.healthConnect,
        healthConnectRecordId: d.sourceId,
      );
    }));

    return result;
  } catch (e) {
    print('❌ Health Connect Aktivitäten-Import fehlgeschlagen: $e');
    return [];
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
    print('❌ Health Connect Körperdaten-Import fehlgeschlagen: $e');
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
