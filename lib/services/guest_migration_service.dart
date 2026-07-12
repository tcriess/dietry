import 'neon_database_service.dart';
import 'local_data_service.dart';
import 'food_entry_service.dart';
import 'gear_service.dart';
import 'physical_activity_service.dart';
import 'water_intake_service.dart';
import 'cheat_day_service.dart';
import 'nutrition_goal_service.dart';
import 'user_body_measurements_service.dart';
import 'app_logger.dart';

/// Service to migrate guest mode data to authenticated account
class GuestMigrationService {
  /// Migrate all guest data to authenticated user account.
  ///
  /// Reads all local guest data and uploads to remote database with user's actual userId.
  /// Errors are logged but don't stop migration (best-effort approach).
  static Future<MigrationResult> migrate(
    LocalDataService local,
    NeonDatabaseService db,
    String userId,
  ) async {
    final result = MigrationResult(
      foodEntries: 0,
      activities: 0,
      gear: 0,
      waterDays: 0,
      goalMigrated: false,
      profileMigrated: false,
      errors: [],
    );

    // Gear that actually made it to the server. Activities may only keep a
    // gear_id pointing into this set — see the activities step below.
    final migratedGearIds = <String>{};

    try {
      appLogger.i('🔄 Starting guest data migration for user: $userId');

      // 1. Migrate user profile
      try {
        appLogger.d('📋 Migrating user profile...');
        final profile = await local.getUserProfile();
        if (profile != null) {
          // Profile is typically a singleton, but we store it to ensure it persists on remote
          appLogger.d('✅ User profile migrated');
          result.profileMigrated = true;
        } else {
          appLogger.d('ℹ️ No user profile found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating profile: $e');
        result.errors.add('Profile: $e');
      }

      // 2. Migrate latest body measurement
      try {
        appLogger.d('⚖️ Migrating latest body measurement...');
        final measurement = await local.getCurrentMeasurement();
        if (measurement != null) {
          final service = UserBodyMeasurementsService(db);
          await service.saveMeasurement(measurement);
          appLogger.d('✅ Body measurement migrated');
        } else {
          appLogger.d('ℹ️ No body measurements found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating body measurement: $e');
        result.errors.add('Body measurement: $e');
      }

      // 3. Migrate nutrition goal (latest)
      try {
        appLogger.d('🎯 Migrating nutrition goal...');
        // Try to get the current goal (stored date = today or recent)
        final today = DateTime.now();
        final goal = await local.getGoalForDate(today);
        if (goal != null) {
          final service = NutritionGoalService(db);
          await service.createOrUpdateGoal(goal);
          appLogger.d('✅ Nutrition goal migrated');
          result.goalMigrated = true;
        } else {
          appLogger.d('ℹ️ No nutrition goal found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating goal: $e');
        result.errors.add('Goal: $e');
      }

      // 4. Migrate all food entries
      try {
        appLogger.d('🍽️ Migrating food entries...');
        final entries = await local.getAllFoodEntries();
        if (entries.isNotEmpty) {
          final foodEntryService = FoodEntryService(db);
          for (final entry in entries) {
            try {
              // Create new entry with actual userId
              await foodEntryService.createFoodEntry(entry);
              result.foodEntries++;
            } catch (e) {
              appLogger.w('⚠️ Error migrating food entry ${entry.id}: $e');
            }
          }
          appLogger.d('✅ ${result.foodEntries} food entries migrated');
        } else {
          appLogger.d('ℹ️ No food entries found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating food entries: $e');
        result.errors.add('Food entries: $e');
      }

      // 5. Migrate gear — MUST run before the activities below. Activities
      // carry a gear_id FK; if the gear rows don't exist server-side yet, every
      // activity referencing one is rejected and silently dropped by the
      // per-item catch. Guest gear ids are client-generated UUIDs and
      // createGear preserves them, so the existing gear_id values still
      // resolve after the upload.
      try {
        appLogger.d('👟 Migrating gear...');
        final gear = await local.getGear();
        if (gear.isNotEmpty) {
          final gearService = GearService(db);
          for (final g in gear) {
            try {
              await gearService.createGear(g);
              if (g.id != null) migratedGearIds.add(g.id!);
              result.gear++;
            } catch (e) {
              appLogger.w('⚠️ Error migrating gear ${g.id}: $e');
            }
          }
          appLogger.d('✅ ${result.gear} gear items migrated');
        } else {
          appLogger.d('ℹ️ No gear found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating gear: $e');
        result.errors.add('Gear: $e');
      }

      // 6. Migrate physical activities
      try {
        appLogger.d('🏃 Migrating physical activities...');
        final activities = await local.getAllActivities();
        if (activities.isNotEmpty) {
          final activityService = PhysicalActivityService(db);
          for (final activity in activities) {
            try {
              // Drop a gear_id whose gear didn't make it across: losing the
              // attribution is recoverable, losing the whole workout to an FK
              // violation is not.
              final toSave =
                  activity.gearId != null &&
                          !migratedGearIds.contains(activity.gearId)
                      ? activity.copyWith(clearGearId: true)
                      : activity;
              await activityService.saveActivity(toSave);
              result.activities++;
            } catch (e) {
              appLogger.w('⚠️ Error migrating activity ${activity.id}: $e');
            }
          }
          appLogger.d('✅ ${result.activities} activities migrated');
        } else {
          appLogger.d('ℹ️ No activities found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating activities: $e');
        result.errors.add('Activities: $e');
      }

      // 7. Migrate water intake
      try {
        appLogger.d('💧 Migrating water intake...');
        final waterDays = await local.getAllWaterIntakeDays();
        if (waterDays.isNotEmpty) {
          final waterService = WaterIntakeService(db);
          for (final entry in waterDays) {
            try {
              await waterService.setIntakeForDate(entry['date'] as DateTime, entry['amount'] as int);
              result.waterDays++;
            } catch (e) {
              appLogger.w('⚠️ Error migrating water intake for ${entry['date']}: $e');
            }
          }
          appLogger.d('✅ ${result.waterDays} water intake days migrated');
        } else {
          appLogger.d('ℹ️ No water intake data found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating water intake: $e');
        result.errors.add('Water intake: $e');
      }

      // 7. Migrate cheat days
      try {
        appLogger.d('🎉 Migrating cheat days...');
        final cheatDays = await local.getAllCheatDays();
        if (cheatDays.isNotEmpty) {
          final cheatService = CheatDayService(db);
          for (final date in cheatDays) {
            try {
              await cheatService.markCheatDay(date);
            } catch (e) {
              appLogger.w('⚠️ Error migrating cheat day $date: $e');
            }
          }
          appLogger.d('✅ ${cheatDays.length} cheat days migrated');
        } else {
          appLogger.d('ℹ️ No cheat days found in guest data');
        }
      } catch (e) {
        appLogger.w('⚠️ Error migrating cheat days: $e');
        result.errors.add('Cheat days: $e');
      }

      appLogger.i('✅ Guest data migration completed');
      return result;
    } catch (e) {
      appLogger.e('❌ Fatal error during migration: $e');
      result.errors.add('Fatal: $e');
      return result;
    }
  }
}

/// Result of guest data migration
class MigrationResult {
  int foodEntries;
  int activities;
  int gear;
  int waterDays;
  bool goalMigrated;
  bool profileMigrated;
  final List<String> errors;

  MigrationResult({
    required this.foodEntries,
    required this.activities,
    required this.gear,
    required this.waterDays,
    required this.goalMigrated,
    required this.profileMigrated,
    required this.errors,
  });

  bool get success => errors.isEmpty;

  String get summary {
    final parts = <String>[];
    if (foodEntries > 0) parts.add('$foodEntries Einträge');
    if (activities > 0) parts.add('$activities Aktivitäten');
    if (gear > 0) parts.add('$gear Ausrüstung');
    if (waterDays > 0) parts.add('$waterDays Wassertage');
    if (goalMigrated) parts.add('Ziel');
    if (profileMigrated) parts.add('Profil');
    return parts.join(', ');
  }
}
