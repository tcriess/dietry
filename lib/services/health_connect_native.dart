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
    final granted = await _health.requestAuthorization(
      [..._activityTypes, ..._bodyTypes],
      permissions: [
        ..._activityTypes.map((_) => HealthDataAccess.READ),
        ..._bodyTypes.map((_) => HealthDataAccess.READ),
      ],
    );

    if (granted) {
      print('✅ Health Connect Berechtigungen gewährt');
      // Verify permissions actually work by checking one data type
      try {
        final now = DateTime.now();
        final test = await _health.getHealthDataFromTypes(
          types: [HealthDataType.STEPS],
          startTime: now.subtract(const Duration(hours: 1)),
          endTime: now,
        );
        print('✅ Berechtigungen funktionieren: ${test.length} Datenpunkte abgerufen');
      } catch (e) {
        print('⚠️ Berechtigungen gewährt aber Abfrage fehlgeschlagen: $e');
        print('💡 Bitte öffne Health Connect > Einstellungen > Berechtigungen und aktiviere Dietry manuell');
        return false;
      }
    }

    return granted;
  } catch (e) {
    print('❌ Health Connect Berechtigungen fehlgeschlagen: $e');
    return false;
  }
}

Future<List<PhysicalActivity>> fetchHealthActivities({
  required DateTime start,
  required DateTime end,
}) async {
  final result = <PhysicalActivity>[];

  // Query each type separately so one permission error doesn't block all data

  // Structured workouts (WORKOUT type)
  try {
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: start,
      endTime: end,
    );

    result.addAll(data.map((d) {
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
  } catch (e) {
    print('⚠️ WORKOUT data unavailable (permission may not be granted): $e');
  }

  // Simple active calorie burns (log entries without duration info)
  try {
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.ACTIVE_ENERGY_BURNED],
      startTime: start,
      endTime: end,
    );

    result.addAll(data.map((d) {
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
  } catch (e) {
    print('⚠️ ACTIVE_ENERGY_BURNED data unavailable (permission may not be granted): $e');
  }

  // Steps (convert to walking activity since we have permission for this)
  try {
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.STEPS],
      startTime: start,
      endTime: end,
    );

    result.addAll(data
        .map((d) {
          final steps = (d.value as NumericHealthValue).numericValue.toInt();
          final durationMinutes = d.dateTo.difference(d.dateFrom).inMinutes;

          // Skip entries with zero duration (database constraint requires > 0)
          if (durationMinutes <= 0) {
            return null;
          }

          // Generate unique ID from timestamp + steps if sourceId is empty
          // Format: steps_YYYY-MM-DDTHH:MM:SS.mmm_<steps>
          String recordId = d.sourceId;
          if (recordId.isEmpty) {
            recordId = 'steps_${d.dateFrom.toIso8601String()}_${steps}';
          }

          // Rough estimate: ~100 calories per 10,000 steps (varies by weight/intensity)
          final estimatedCalories = (steps / 10000.0) * 100.0;

          return PhysicalActivity(
            activityType: ActivityType.other,
            activityName: 'Walking ($steps steps)',
            startTime: d.dateFrom,
            endTime: d.dateTo,
            durationMinutes: durationMinutes,
            caloriesBurned: estimatedCalories > 0 ? estimatedCalories : null,
            distanceKm: null,
            source: DataSource.healthConnect,
            healthConnectRecordId: recordId,
          );
        })
        .whereType<PhysicalActivity>()
        .toList());

    print('✅ Found ${data.length} STEPS data points - imported ${result.length} activities');
  } catch (e) {
    print('⚠️ STEPS data unavailable (permission may not be granted): $e');
  }

  return result;
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
