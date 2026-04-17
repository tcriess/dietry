import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert' show jsonEncode, jsonDecode;
import '../models/models.dart';
import '../models/food_portion.dart';
import 'app_logger.dart';

/// Local SQLite database service for guest mode.
///
/// Stores food entries, nutrition goals, activities, water intake, and cheat days
/// all locally without any network calls. All data is associated with a fixed 'guest' userId.
class LocalDataService {
  static final LocalDataService instance = LocalDataService._();
  LocalDataService._();

  static const String _userId = 'guest';
  static const String _dbName = 'dietry_local.db';
  static const int _version = 4;  // Version 4: fixed physical_activities schema

  Database? _db;
  bool _initialized = false;

  Future<void> init() async {
    appLogger.d('[LocalDataService.init] Starting...');
    if (_initialized && _db != null) {
      appLogger.d('[LocalDataService.init] Already initialized, returning early');
      return;
    }

    try {
      if (kIsWeb) {
        appLogger.d('[LocalDataService.init] Web platform detected - using IndexedDB via idb_shim');
        await _initWeb();
      } else {
        appLogger.d('[LocalDataService.init] Native platform - using sqflite');
        appLogger.d('[LocalDataService.init] Getting database path...');
        final dbPath = await getDatabasesPath();
        appLogger.d('[LocalDataService.init] dbPath=$dbPath');

        final fullPath = path.join(dbPath, _dbName);
        appLogger.d('[LocalDataService.init] fullPath=$fullPath');

        appLogger.d('[LocalDataService.init] Opening database...');
        _db = await openDatabase(
          fullPath,
          version: _version,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        appLogger.d('[LocalDataService.init] Database opened successfully');
      }

      _initialized = true;
      appLogger.d('[LocalDataService.init] Set _initialized=true');

      appLogger.i('✅ LocalDataService initialized');
    } catch (e) {
      appLogger.e('❌ Error initializing LocalDataService: $e');
      rethrow;
    }
  }

  /// Initialize web storage using IndexedDB
  Future<void> _initWeb() async {
    try {
      appLogger.d('[LocalDataService._initWeb] Opening IndexedDB database...');
      // Use idb_shim's getIdbFactory function (if available) or direct access
      // For now, we'll defer actual IndexedDB operations to individual CRUD methods
      // and use a simpler approach with localStorage for MVP
      appLogger.d('[LocalDataService._initWeb] IndexedDB support prepared');
    } catch (e) {
      appLogger.e('❌ Error initializing web storage: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    try {
      // food_entries table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS food_entries (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          food_id TEXT,
          meal_template_id TEXT,
          entry_date TEXT NOT NULL,
          meal_type TEXT NOT NULL,
          name TEXT NOT NULL,
          amount REAL NOT NULL,
          unit TEXT NOT NULL,
          calories REAL NOT NULL,
          protein REAL NOT NULL,
          fat REAL NOT NULL,
          carbs REAL NOT NULL,
          fiber REAL,
          sugar REAL,
          sodium REAL,
          saturated_fat REAL,
          notes TEXT,
          is_liquid INTEGER NOT NULL DEFAULT 0,
          amount_ml REAL,
          is_meal INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // nutrition_goals table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS nutrition_goals (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          valid_from TEXT NOT NULL,
          calories REAL NOT NULL,
          protein REAL NOT NULL,
          fat REAL NOT NULL,
          carbs REAL NOT NULL,
          fiber REAL,
          sugar REAL,
          sodium REAL,
          saturated_fat REAL,
          macro_only INTEGER NOT NULL DEFAULT 0,
          tracking_method TEXT,
          water_goal_ml INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // physical_activities table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS physical_activities (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          activity_type TEXT NOT NULL,
          activity_id TEXT,
          activity_name TEXT,
          start_time TEXT NOT NULL,
          end_time TEXT NOT NULL,
          duration_minutes INTEGER,
          calories_burned REAL,
          distance_km REAL,
          steps INTEGER,
          avg_heart_rate REAL,
          notes TEXT,
          source TEXT NOT NULL DEFAULT 'manual',
          health_connect_record_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // water_intake table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS water_intake (
          date TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          amount_ml INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // cheat_days table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cheat_days (
          date TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');

      // user_profile table (singleton for guest user)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_profile (
          user_id TEXT PRIMARY KEY,
          birthdate TEXT,
          height REAL,
          gender TEXT,
          activity_level TEXT,
          weight_goal TEXT,
          updated_at TEXT NOT NULL
        )
      ''');

      // user_body_measurements table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_body_measurements (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          weight REAL NOT NULL,
          body_fat_percentage REAL,
          muscle_mass_kg REAL,
          waist_cm REAL,
          measured_at TEXT NOT NULL,
          notes TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(user_id, measured_at)
        )
      ''');

      // guest_foods table: locally created foods in guest mode
      await db.execute('''
        CREATE TABLE IF NOT EXISTS guest_foods (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          brand TEXT,
          category TEXT,
          calories REAL NOT NULL,
          protein REAL NOT NULL,
          fat REAL NOT NULL,
          carbs REAL NOT NULL,
          fiber REAL,
          sugar REAL,
          sodium REAL,
          saturated_fat REAL,
          portions TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      appLogger.i('✅ LocalDataService tables created');
    } catch (e) {
      appLogger.e('❌ Error creating tables: $e');
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    appLogger.i('📦 LocalDataService migration: $oldVersion → $newVersion');

    if (oldVersion < 2) {
      // Add missing columns to nutrition_goals
      try {
        await db.execute('ALTER TABLE nutrition_goals ADD COLUMN tracking_method TEXT');
        appLogger.d('✅ Added tracking_method column to nutrition_goals');
      } catch (e) {
        appLogger.d('ℹ️ tracking_method column already exists: $e');
      }

      try {
        await db.execute('ALTER TABLE nutrition_goals ADD COLUMN water_goal_ml INTEGER');
        appLogger.d('✅ Added water_goal_ml column to nutrition_goals');
      } catch (e) {
        appLogger.d('ℹ️ water_goal_ml column already exists: $e');
      }

      // Create new tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_profile (
          user_id TEXT PRIMARY KEY,
          birthdate TEXT,
          height REAL,
          gender TEXT,
          activity_level TEXT,
          weight_goal TEXT,
          updated_at TEXT NOT NULL
        )
      ''');
      appLogger.d('✅ Created user_profile table');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_body_measurements (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          weight REAL NOT NULL,
          body_fat_percentage REAL,
          muscle_mass_kg REAL,
          waist_cm REAL,
          measured_at TEXT NOT NULL,
          notes TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(user_id, measured_at)
        )
      ''');
      appLogger.d('✅ Created user_body_measurements table');

      appLogger.i('✅ Migration 1→2 complete');
    }

    if (oldVersion < 3) {
      // Version 3: Add guest_foods table for locally created foods
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS guest_foods (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT,
            category TEXT,
            calories REAL NOT NULL,
            protein REAL NOT NULL,
            fat REAL NOT NULL,
            carbs REAL NOT NULL,
            fiber REAL,
            sugar REAL,
            sodium REAL,
            saturated_fat REAL,
            portions TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        appLogger.d('✅ Created guest_foods table');
        appLogger.i('✅ Migration 2→3 complete');
      } catch (e) {
        appLogger.e('❌ Error in migration 2→3: $e');
      }
    }

    if (oldVersion < 4) {
      // Version 4: Fix physical_activities schema to match PhysicalActivity model
      try {
        // Drop old table and create new one with correct schema
        await db.execute('DROP TABLE IF EXISTS physical_activities');
        appLogger.d('   ✅ Dropped old physical_activities table');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS physical_activities (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            activity_type TEXT NOT NULL,
            activity_id TEXT,
            activity_name TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            duration_minutes INTEGER,
            calories_burned REAL,
            distance_km REAL,
            steps INTEGER,
            avg_heart_rate REAL,
            notes TEXT,
            source TEXT NOT NULL DEFAULT 'manual',
            health_connect_record_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        appLogger.d('✅ Created new physical_activities table with correct schema');
        appLogger.i('✅ Migration 3→4 complete');
      } catch (e) {
        appLogger.e('❌ Error in migration 3→4: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Food Entries
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<FoodEntry>> getFoodEntriesForDate(DateTime date) async {
    if (!_initialized || _db == null) return [];
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final results = await _db!.query(
        'food_entries',
        where: 'user_id = ? AND entry_date = ?',
        whereArgs: [_userId, dateStr],
        orderBy: 'created_at DESC',
      );
      return results.map((json) {
        // Convert SQLite 0/1 back to boolean (create new map since results are read-only)
        final mutableJson = Map<String, dynamic>.from(json);
        mutableJson['is_liquid'] = (mutableJson['is_liquid'] as int? ?? 0) != 0;
        mutableJson['is_meal'] = (mutableJson['is_meal'] as int? ?? 0) != 0;
        return FoodEntry.fromJson(mutableJson);
      }).toList();
    } catch (e) {
      appLogger.e('❌ Error fetching food entries: $e');
      return [];
    }
  }

  Future<FoodEntry> createFoodEntry(FoodEntry entry) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final id = const Uuid().v4();
      final now = DateTime.now();
      final entryWithIds = entry.copyWith(
        id: id,
        userId: _userId,
        createdAt: now,
        updatedAt: now,
      );

      // Convert to JSON and fix SQLite incompatibilities
      final data = entryWithIds.toJson();
      // SQLite doesn't accept bool; convert to 0/1
      data['is_liquid'] = entryWithIds.isLiquid ? 1 : 0;
      data['is_meal'] = entryWithIds.isMeal ? 1 : 0;

      await _db!.insert('food_entries', data);
      appLogger.d('✅ Created food entry: $id');
      return entryWithIds;
    } catch (e) {
      appLogger.e('❌ Error creating food entry: $e');
      rethrow;
    }
  }

  Future<FoodEntry> updateFoodEntry(FoodEntry entry) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final updated = entry.copyWith(updatedAt: DateTime.now());

      // Convert to JSON and fix SQLite incompatibilities
      final data = updated.toJson();
      // SQLite doesn't accept bool; convert to 0/1
      data['is_liquid'] = updated.isLiquid ? 1 : 0;
      data['is_meal'] = updated.isMeal ? 1 : 0;

      await _db!.update(
        'food_entries',
        data,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      appLogger.d('✅ Updated food entry: ${entry.id}');
      return updated;
    } catch (e) {
      appLogger.e('❌ Error updating food entry: $e');
      rethrow;
    }
  }

  Future<void> deleteFoodEntry(String id) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      await _db!.delete('food_entries', where: 'id = ?', whereArgs: [id]);
      appLogger.d('✅ Deleted food entry: $id');
    } catch (e) {
      appLogger.e('❌ Error deleting food entry: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Nutrition Goals
  // ─────────────────────────────────────────────────────────────────────────

  Future<NutritionGoal?> getGoalForDate(DateTime date) async {
    if (!_initialized) return null;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('nutrition_goal');
        if (jsonStr == null) return null;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        // Convert 0/1 back to boolean
        json['macro_only'] = (json['macro_only'] as int? ?? 0) != 0;
        return NutritionGoal.fromJson(json);
      } else {
        if (_db == null) return null;
        final dateStr = date.toIso8601String().split('T')[0];
        final results = await _db!.query(
          'nutrition_goals',
          where: 'user_id = ? AND valid_from <= ?',
          whereArgs: [_userId, dateStr],
          orderBy: 'valid_from DESC',
          limit: 1,
        );
        if (results.isEmpty) return null;

        // Convert SQLite 0/1 back to boolean (create new map since results are read-only)
        final json = Map<String, dynamic>.from(results.first);
        json['macro_only'] = (json['macro_only'] as int? ?? 0) != 0;
        return NutritionGoal.fromJson(json);
      }
    } catch (e) {
      appLogger.e('❌ Error fetching nutrition goal: $e');
      return null;
    }
  }

  Future<NutritionGoal> upsertGoal(NutritionGoal goal) async {
    if (!_initialized) throw Exception('LocalDataService not initialized');
    try {
      final id = goal.id ?? const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      // valid_from is required by DB schema; use today if not provided
      final validFromStr = goal.validFrom != null
          ? goal.validFrom!.toIso8601String().split('T')[0]
          : DateTime.now().toIso8601String().split('T')[0];

      // Build data map with all supported columns
      final data = {
        'id': id,
        'user_id': _userId,
        'calories': goal.calories,
        'protein': goal.protein,
        'fat': goal.fat,
        'carbs': goal.carbs,
        'valid_from': validFromStr,
        'macro_only': goal.macroOnly ? 1 : 0,
        'tracking_method': goal.trackingMethod?.name,
        'water_goal_ml': goal.waterGoalMl,
        'created_at': now,
        'updated_at': now,
      };

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nutrition_goal', jsonEncode(data));
        appLogger.d('✅ Upserted nutrition goal (web): $id');
      } else {
        if (_db == null) throw Exception('LocalDataService database not initialized');
        await _db!.insert(
          'nutrition_goals',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        appLogger.d('✅ Upserted nutrition goal: $id');
      }

      final goalWithId = NutritionGoal(
        id: id,
        userId: _userId,
        calories: goal.calories,
        protein: goal.protein,
        fat: goal.fat,
        carbs: goal.carbs,
        validFrom: goal.validFrom,
        trackingMethod: goal.trackingMethod,
        waterGoalMl: goal.waterGoalMl,
        macroOnly: goal.macroOnly,
      );

      return goalWithId;
    } catch (e) {
      appLogger.e('❌ Error upserting nutrition goal: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Physical Activities
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<PhysicalActivity>> getActivitiesForDate(DateTime date) async {
    if (!_initialized || _db == null) return [];
    try {
      // Query activities that start on the given date
      final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toIso8601String();

      final results = await _db!.query(
        'physical_activities',
        where: 'user_id = ? AND start_time >= ? AND start_time <= ?',
        whereArgs: [_userId, startOfDay, endOfDay],
        orderBy: 'created_at DESC',
      );
      return results.map((json) => PhysicalActivity.fromJson(json)).toList();
    } catch (e) {
      appLogger.e('❌ Error fetching activities: $e');
      return [];
    }
  }

  Future<PhysicalActivity> createActivity(PhysicalActivity activity) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final id = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final activityWithId = PhysicalActivity(
        id: id,
        activityType: activity.activityType,
        activityId: activity.activityId,
        activityName: activity.activityName,
        startTime: activity.startTime,
        endTime: activity.endTime,
        durationMinutes: activity.durationMinutes,
        caloriesBurned: activity.caloriesBurned,
        distanceKm: activity.distanceKm,
        steps: activity.steps,
        avgHeartRate: activity.avgHeartRate,
        notes: activity.notes,
        source: activity.source,
        healthConnectRecordId: activity.healthConnectRecordId,
      );

      // Add user_id and timestamps which are required in the local schema
      final data = activityWithId.toJson();
      data['user_id'] = _userId;
      data['created_at'] = now;
      data['updated_at'] = now;

      await _db!.insert('physical_activities', data);
      appLogger.d('✅ Created activity: $id');
      return activityWithId;
    } catch (e) {
      appLogger.e('❌ Error creating activity: $e');
      rethrow;
    }
  }

  Future<PhysicalActivity> updateActivity(PhysicalActivity activity) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final now = DateTime.now().toIso8601String();
      final data = activity.toJson();
      data['user_id'] = _userId;
      data['updated_at'] = now;

      await _db!.update(
        'physical_activities',
        data,
        where: 'id = ?',
        whereArgs: [activity.id],
      );
      appLogger.d('✅ Updated activity: ${activity.id}');
      return activity;
    } catch (e) {
      appLogger.e('❌ Error updating activity: $e');
      rethrow;
    }
  }

  Future<void> deleteActivity(String id) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      await _db!.delete('physical_activities', where: 'id = ?', whereArgs: [id]);
      appLogger.d('✅ Deleted activity: $id');
    } catch (e) {
      appLogger.e('❌ Error deleting activity: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Water Intake
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> getWaterIntakeForDate(DateTime date) async {
    if (!_initialized || _db == null) return 0;
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final result = await _db!.query(
        'water_intake',
        where: 'date = ?',
        whereArgs: [dateStr],
        limit: 1,
      );
      if (result.isEmpty) return 0;
      return (result.first['amount_ml'] as int?) ?? 0;
    } catch (e) {
      appLogger.e('❌ Error fetching water intake: $e');
      return 0;
    }
  }

  Future<void> setWaterIntakeForDate(DateTime date, int amountMl) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final now = DateTime.now().toIso8601String();
      await _db!.insert(
        'water_intake',
        {
          'date': dateStr,
          'user_id': _userId,
          'amount_ml': amountMl,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      appLogger.d('✅ Set water intake for $dateStr: ${amountMl}ml');
    } catch (e) {
      appLogger.e('❌ Error setting water intake: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cheat Days
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> isCheatDay(DateTime date) async {
    if (!_initialized || _db == null) return false;
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final result = await _db!.query(
        'cheat_days',
        where: 'date = ?',
        whereArgs: [dateStr],
      );
      return result.isNotEmpty;
    } catch (e) {
      appLogger.e('❌ Error checking cheat day: $e');
      return false;
    }
  }

  Future<void> markCheatDay(DateTime date) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final now = DateTime.now().toIso8601String();
      await _db!.insert(
        'cheat_days',
        {
          'date': dateStr,
          'user_id': _userId,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      appLogger.d('✅ Marked cheat day: $dateStr');
    } catch (e) {
      appLogger.e('❌ Error marking cheat day: $e');
      rethrow;
    }
  }

  Future<void> unmarkCheatDay(DateTime date) async {
    if (!_initialized || _db == null) throw Exception('LocalDataService not initialized');
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      await _db!.delete('cheat_days', where: 'date = ?', whereArgs: [dateStr]);
      appLogger.d('✅ Unmarked cheat day: $dateStr');
    } catch (e) {
      appLogger.e('❌ Error unmarking cheat day: $e');
      rethrow;
    }
  }

  /// Get cheat day count for the month of [date]
  Future<int> countCheatDaysInMonth(DateTime date) async {
    if (!_initialized || _db == null) return 0;
    try {
      final year = date.year;
      final month = date.month.toString().padLeft(2, '0');
      final prefix = '$year-$month';
      final result = await _db!.rawQuery(
        'SELECT COUNT(*) as count FROM cheat_days WHERE date LIKE ?',
        ['$prefix%'],
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      appLogger.e('❌ Error counting cheat days: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // User Profile (guest mode)
  // ─────────────────────────────────────────────────────────────────────────

  Future<UserProfile?> getUserProfile() async {
    if (!_initialized) return null;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('user_profile');
        if (jsonStr == null) return null;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return UserProfile.fromJson(json);
      } else {
        if (_db == null) return null;
        final result = await _db!.query(
          'user_profile',
          where: 'user_id = ?',
          whereArgs: [_userId],
          limit: 1,
        );
        if (result.isEmpty) return null;

        final json = Map<String, dynamic>.from(result.first);
        return UserProfile.fromJson(json);
      }
    } catch (e) {
      appLogger.e('❌ Error fetching user profile: $e');
      return null;
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    if (!_initialized) throw Exception('LocalDataService not initialized');
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().toIso8601String();
        final data = {
          'user_id': _userId,
          'birthdate': profile.birthdate?.toIso8601String().split('T')[0],
          'height': profile.height,
          'gender': profile.gender?.name,
          'activity_level': profile.activityLevel?.name,
          'weight_goal': profile.weightGoal?.name,
          'updated_at': now,
        };
        await prefs.setString('user_profile', jsonEncode(data));
        appLogger.d('✅ Saved user profile (web)');
      } else {
        if (_db == null) throw Exception('LocalDataService database not initialized');
        final now = DateTime.now().toIso8601String();
        final data = {
          'user_id': _userId,
          'birthdate': profile.birthdate?.toIso8601String().split('T')[0],
          'height': profile.height,
          'gender': profile.gender?.name,
          'activity_level': profile.activityLevel?.name,
          'weight_goal': profile.weightGoal?.name,
          'updated_at': now,
        };

        await _db!.insert(
          'user_profile',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        appLogger.d('✅ Saved user profile');
      }
    } catch (e) {
      appLogger.e('❌ Error saving user profile: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Body Measurements (guest mode)
  // ─────────────────────────────────────────────────────────────────────────

  Future<UserBodyMeasurement?> getCurrentMeasurement() async {
    if (!_initialized) return null;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('current_measurement');
        if (jsonStr == null) return null;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return UserBodyMeasurement.fromJson(json);
      } else {
        if (_db == null) return null;
        final result = await _db!.query(
          'user_body_measurements',
          where: 'user_id = ?',
          whereArgs: [_userId],
          orderBy: 'measured_at DESC',
          limit: 1,
        );
        if (result.isEmpty) return null;

        final json = Map<String, dynamic>.from(result.first);
        return UserBodyMeasurement.fromJson(json);
      }
    } catch (e) {
      appLogger.e('❌ Error fetching current measurement: $e');
      return null;
    }
  }

  Future<void> saveMeasurement(UserBodyMeasurement measurement) async {
    if (!_initialized) throw Exception('LocalDataService not initialized');
    try {
      final id = measurement.id ?? const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final measuredAtStr = measurement.measuredAt.toIso8601String();

      final data = {
        'id': id,
        'user_id': _userId,
        'weight': measurement.weight,
        'body_fat_percentage': measurement.bodyFatPercentage,
        'muscle_mass_kg': measurement.muscleMassKg,
        'waist_cm': measurement.waistCm,
        'measured_at': measuredAtStr,
        'notes': measurement.notes,
        'created_at': now,
      };

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_measurement', jsonEncode(data));
        appLogger.d('✅ Saved body measurement (web)');
      } else {
        if (_db == null) throw Exception('LocalDataService database not initialized');
        await _db!.insert(
          'user_body_measurements',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        appLogger.d('✅ Saved body measurement');
      }
    } catch (e) {
      appLogger.e('❌ Error saving body measurement: $e');
      rethrow;
    }
  }

  /// Close the database (cleanup)
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _initialized = false;
      appLogger.i('✅ LocalDataService closed');
    }
  }

  /// Save a food created locally in guest mode.
  /// Returns the saved FoodItem with the new ID.
  Future<FoodItem> saveGuestFood(FoodItem food) async {
    if (kIsWeb) {
      appLogger.w('⚠️ Guest food saving not yet implemented for web');
      return food;
    }
    if (_db == null) {
      throw Exception('Database not initialized');
    }

    final foodWithId = food.copyWith(id: food.id.isEmpty ? const Uuid().v4() : food.id);

    await _db!.insert('guest_foods', {
      'id': foodWithId.id,
      'name': foodWithId.name,
      'brand': foodWithId.brand,
      'category': foodWithId.category,
      'calories': foodWithId.calories,
      'protein': foodWithId.protein,
      'fat': foodWithId.fat,
      'carbs': foodWithId.carbs,
      'fiber': foodWithId.fiber,
      'sugar': foodWithId.sugar,
      'sodium': foodWithId.sodium,
      'saturated_fat': foodWithId.saturatedFat,
      'portions': foodWithId.portions.isEmpty
          ? null
          : jsonEncode(foodWithId.portions.map((p) => {
              'name': p.name,
              'amount_g': p.amountG,
            }).toList()),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    appLogger.i('✅ Guest food saved locally: ${foodWithId.name}');
    return foodWithId;
  }

  /// Search locally stored guest foods by name/brand.
  Future<List<FoodItem>> searchGuestFoods(String query) async {
    if (kIsWeb) {
      return [];
    }
    if (_db == null) {
      return [];
    }

    final results = await _db!.query(
      'guest_foods',
      where: 'name LIKE ? OR brand LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: 50,
    );

    return results.map((row) {
      final portionsJson = row['portions'] as String?;
      final List<FoodPortion> portions;
      if (portionsJson != null) {
        final jsonList = jsonDecode(portionsJson) as List;
        portions = jsonList
            .map((p) => FoodPortion(
              name: p['name'] as String,
              amountG: (p['amount_g'] as num).toDouble(),
            ))
            .toList();
      } else {
        portions = [];
      }

      return FoodItem(
        id: row['id'] as String,
        name: row['name'] as String,
        brand: row['brand'] as String?,
        category: row['category'] as String?,
        calories: (row['calories'] as num).toDouble(),
        protein: (row['protein'] as num).toDouble(),
        fat: (row['fat'] as num).toDouble(),
        carbs: (row['carbs'] as num).toDouble(),
        fiber: (row['fiber'] as num?)?.toDouble(),
        sugar: (row['sugar'] as num?)?.toDouble(),
        sodium: (row['sodium'] as num?)?.toDouble(),
        saturatedFat: (row['saturated_fat'] as num?)?.toDouble(),
        portions: portions,
        isPublic: false,
        isApproved: false,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
    }).toList();
  }

  /// Get all food entries from database (for migration)
  Future<List<FoodEntry>> getAllFoodEntries() async {
    if (kIsWeb || _db == null) return [];

    try {
      final maps = await _db!.query('food_entries', orderBy: 'entry_date ASC');
      return maps.map((map) => FoodEntry.fromJson(map)).toList();
    } catch (e) {
      appLogger.w('⚠️ Error getting all food entries: $e');
      return [];
    }
  }

  /// Get all physical activities from database (for migration)
  Future<List<PhysicalActivity>> getAllActivities() async {
    if (kIsWeb || _db == null) return [];

    try {
      final maps = await _db!.query('physical_activities', orderBy: 'activity_date ASC');
      return maps.map((map) => PhysicalActivity.fromJson(map)).toList();
    } catch (e) {
      appLogger.w('⚠️ Error getting all activities: $e');
      return [];
    }
  }

  /// Get all water intake entries from database (for migration)
  /// Returns list of maps with 'date' and 'amount' keys
  Future<List<Map<String, dynamic>>> getAllWaterIntakeDays() async {
    if (kIsWeb || _db == null) return [];

    try {
      final maps = await _db!.query('water_intake', orderBy: 'intake_date ASC');
      return maps.map((map) => {
        'date': DateTime.parse(map['intake_date'] as String),
        'amount': map['amount_ml'] as int,
      }).toList();
    } catch (e) {
      appLogger.w('⚠️ Error getting all water intake days: $e');
      return [];
    }
  }

  /// Get all cheat days from database (for migration)
  /// Returns list of dates that are marked as cheat days
  Future<List<DateTime>> getAllCheatDays() async {
    if (kIsWeb || _db == null) return [];

    try {
      final maps = await _db!.query(
        'cheat_days',
        where: 'is_cheat_day = ?',
        whereArgs: [1],
        orderBy: 'cheat_date ASC',
      );
      return maps.map((map) => DateTime.parse(map['cheat_date'] as String)).toList();
    } catch (e) {
      appLogger.w('⚠️ Error getting all cheat days: $e');
      return [];
    }
  }

  /// Delete all guest data from database and shared preferences
  Future<void> clearAll() async {
    try {
      if (kIsWeb) {
        // Web: Clear SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('nutrition_goal');
        await prefs.remove('user_profile');
        await prefs.remove('current_measurement');
        appLogger.d('✅ Cleared all guest data from SharedPreferences (web)');
      } else {
        // Native: Clear all tables
        if (_db == null) {
          appLogger.w('⚠️ Database not initialized, skipping clearAll');
          return;
        }
        final tables = [
          'food_entries',
          'nutrition_goals',
          'physical_activities',
          'water_intake',
          'cheat_days',
          'user_profile',
          'user_body_measurements',
          'guest_foods',
        ];
        for (final table in tables) {
          await _db!.delete(table);
          appLogger.d('   ✅ Cleared $table');
        }
        appLogger.i('✅ All guest data cleared from database');
      }
    } catch (e) {
      appLogger.e('❌ Error clearing guest data: $e');
      rethrow;
    }
  }
}
