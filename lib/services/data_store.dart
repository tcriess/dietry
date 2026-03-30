import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'food_entry_service.dart';
import 'physical_activity_service.dart';
import 'nutrition_goal_service.dart';
import 'water_intake_service.dart';
import 'cheat_day_service.dart';
import 'streak_service.dart';
import 'neon_database_service.dart';
import '../app_features.dart';

/// Singleton ChangeNotifier that is the single source of truth for the
/// current day's food entries, activities and nutrition goal.
///
/// All screens read from here; all write operations (add/edit/delete)
/// update this store immediately (optimistic) so the UI reacts instantly
/// without waiting for the network round-trip.
class DataStore extends ChangeNotifier {
  static final DataStore instance = DataStore._();
  DataStore._();

  List<FoodEntry> _foodEntries = [];
  List<PhysicalActivity> _activities = [];
  NutritionGoal? _goal;
  int _waterIntakeMl = 0;
  bool _isCheatDay = false;
  int _streak = 0;
  int _bestStreak = 0;
  List<int> _pendingMilestones = [];
  bool _isLoading = false;
  bool _isInitialLoading = true;

  NeonDatabaseService? _db;

  // ── Delta-Sync Zeitstempel ─────────────────────────────────────────────────
  // Null = noch kein Sync für den aktuellen Tag → immer Full-Fetch.
  // Wird bei Tag-Wechsel (Full-Load) zurückgesetzt.
  DateTime? _lastEntriesSync;
  DateTime? _lastActivitiesSync;

  List<FoodEntry> get foodEntries => _foodEntries;
  List<PhysicalActivity> get activities => _activities;
  NutritionGoal? get goal => _goal;
  int get waterIntakeMl => _waterIntakeMl;
  bool get isCheatDay => _isCheatDay;
  int get streak => _streak;
  int get bestStreak => _bestStreak;
  List<int> get pendingMilestones => List.unmodifiable(_pendingMilestones);
  bool get isLoading => _isLoading;

  /// True until the very first loadDay() call completes.
  bool get isInitialLoading => _isInitialLoading;

  void init(NeonDatabaseService db) {
    _db = db;
  }

  // ── Remote load ───────────────────────────────────────────────────────────

  /// Fetch data for [date] from the server.
  ///
  /// [silent]  — kein Loading-Overlay (Hintergrund-Refresh).
  /// [delta]   — nur geänderte Records holen (ID-Set-Abgleich).
  ///             Setzt voraus dass [silent] true ist; wird von [_silentRefresh]
  ///             übergeben. Bei Tag-Wechsel immer false → Full-Fetch + Reset.
  Future<void> loadDay(DateTime date, {bool silent = false, bool delta = false}) async {
    if (_db == null) return;
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    if (delta) {
      // Delta: nur Entries + Activities delta-fetchen.
      // Goal + Water sind single-row und trivial leicht → immer full.
      await Future.wait([
        _loadGoal(date),
        _loadEntriesDelta(date),
        _loadActivitiesDelta(date),
        _loadWaterIntake(date),
        _loadCheatDay(date),
      ]);
    } else {
      // Full-Fetch: Sync-Zeitstempel zurücksetzen.
      _lastEntriesSync = null;
      _lastActivitiesSync = null;
      await Future.wait([
        _loadGoal(date),
        _loadEntries(date),
        _loadActivities(date),
        _loadWaterIntake(date),
        _loadCheatDay(date),
        _loadStreak(),
      ]);
    }

    _isLoading = false;
    _isInitialLoading = false;
    notifyListeners();
  }

  // ── Food entries ──────────────────────────────────────────────────────────

  void addFoodEntry(FoodEntry entry) {
    _foodEntries = [..._foodEntries, entry];
    notifyListeners();
    // Cloud: trigger streak update in the background after adding an entry.
    if (AppFeatures.streaks) _checkAndUpdateStreak();
  }

  /// Drains the pending milestone queue. Call this after handling the celebrations.
  void clearPendingMilestones() {
    _pendingMilestones = [];
    // No notifyListeners needed — caller handles the UI.
  }

  void replaceFoodEntry(FoodEntry entry) {
    _foodEntries = _foodEntries.map((e) => e.id == entry.id ? entry : e).toList();
    notifyListeners();
  }

  void removeFoodEntry(String id) {
    _foodEntries = _foodEntries.where((e) => e.id != id).toList();
    notifyListeners();
  }

  // ── Activities ────────────────────────────────────────────────────────────

  void addActivity(PhysicalActivity activity) {
    _activities = [..._activities, activity];
    notifyListeners();
  }

  void addActivities(List<PhysicalActivity> toAdd) {
    _activities = [..._activities, ...toAdd];
    notifyListeners();
  }

  void replaceActivity(PhysicalActivity activity) {
    _activities = _activities.map((a) => a.id == activity.id ? activity : a).toList();
    notifyListeners();
  }

  void removeActivity(String id) {
    _activities = _activities.where((a) => a.id != id).toList();
    notifyListeners();
  }

  // ── Goal ──────────────────────────────────────────────────────────────────

  void setGoal(NutritionGoal? goal) {
    _goal = goal;
    notifyListeners();
  }

  // ── Water ─────────────────────────────────────────────────────────────────

  void setWaterIntakeMl(int ml) {
    _waterIntakeMl = ml.clamp(0, 9999);
    notifyListeners();
  }

  // ── Cheat day ─────────────────────────────────────────────────────────────

  void setCheatDay(bool value) {
    _isCheatDay = value;
    notifyListeners();
  }

  void setStreak(int value) {
    _streak = value;
    notifyListeners();
  }

  /// Recomputes the streak and persists it (cloud only).
  /// Fire-and-forget — called after tracking actions.
  /// Also called externally from [_toggleCheatDay] in main.dart.
  Future<void> checkAndUpdateStreak() => _checkAndUpdateStreak();

  Future<void> _checkAndUpdateStreak() async {
    if (!AppFeatures.streaks || _db == null) return;
    try {
      final newStreak = await CheatDayService(_db!).getStreak();
      final newMilestones = await StreakService(_db!).updateRecord(newStreak);
      _streak = newStreak;
      if (newStreak > _bestStreak) _bestStreak = newStreak;
      if (newMilestones.isNotEmpty) {
        _pendingMilestones = [..._pendingMilestones, ...newMilestones];
      }
      notifyListeners();
    } catch (_) {}
  }

  // ── Private loaders (Full) ────────────────────────────────────────────────

  Future<void> _loadGoal(DateTime date) async {
    try {
      _goal = await NutritionGoalService(_db!).getGoalForDate(date);
    } catch (_) {}
  }

  Future<void> _loadEntries(DateTime date) async {
    try {
      _foodEntries = await FoodEntryService(_db!).getFoodEntriesForDate(date);
      _lastEntriesSync = DateTime.now().toUtc();
    } catch (_) {
      _foodEntries = [];
    }
  }

  Future<void> _loadActivities(DateTime date) async {
    try {
      _activities = await PhysicalActivityService(_db!).getActivitiesForDate(date);
      _lastActivitiesSync = DateTime.now().toUtc();
    } catch (_) {
      _activities = [];
    }
  }

  Future<void> _loadWaterIntake(DateTime date) async {
    try {
      _waterIntakeMl = await WaterIntakeService(_db!).getIntakeForDate(date);
    } catch (_) {
      _waterIntakeMl = 0;
    }
  }

  Future<void> _loadCheatDay(DateTime date) async {
    try {
      _isCheatDay = await CheatDayService(_db!).isCheatDay(date);
    } catch (_) {
      _isCheatDay = false;
    }
  }

  Future<void> _loadStreak() async {
    try {
      if (AppFeatures.streaks) {
        // Cloud: load the persisted record (fast, no recomputation).
        final record = await StreakService(_db!).loadRecord();
        _streak = record?.currentStreak ?? 0;
        _bestStreak = record?.bestStreak ?? 0;
      } else {
        // CE: compute on the fly (not displayed, but kept for cheat day logic).
        _streak = 0;
      }
    } catch (_) {
      _streak = 0;
    }
  }

  // ── Private loaders (Delta) ───────────────────────────────────────────────

  /// Delta-Sync für Food Entries:
  ///   1. Leichte Stub-Query: alle IDs + updated_at für den Tag
  ///   2. Abgleich mit lokalem Cache:
  ///      - ID lokal aber nicht auf Server  → gelöscht, aus Cache entfernen
  ///      - ID auf Server, updated_at neuer → geändert, vollen Record holen
  ///      - ID auf Server, nicht lokal      → neu, vollen Record holen
  ///   3. Nur geänderte/neue Records vollständig laden
  Future<void> _loadEntriesDelta(DateTime date) async {
    // Kein vorheriger Sync → Full-Fetch als Fallback
    if (_lastEntriesSync == null) {
      await _loadEntries(date);
      return;
    }

    try {
      final svc = FoodEntryService(_db!);
      final stubs = await svc.getFoodEntryStubs(date);

      final serverIds = {for (final s in stubs) s.id: s.updatedAt};
      final localIds = {for (final e in _foodEntries) e.id};

      // Gelöschte Einträge: lokal vorhanden, auf Server nicht mehr
      final deletedIds = localIds.difference(serverIds.keys.toSet());
      if (deletedIds.isNotEmpty) {
        _foodEntries = _foodEntries.where((e) => !deletedIds.contains(e.id)).toList();
      }

      // Geänderte oder neue Einträge
      final toFetch = stubs
          .where((s) =>
              !localIds.contains(s.id) ||           // neu
              s.updatedAt.isAfter(_lastEntriesSync!)) // geändert
          .map((s) => s.id)
          .toList();

      if (toFetch.isNotEmpty) {
        final updated = await svc.getFoodEntriesByIds(toFetch);
        for (final entry in updated) {
          final idx = _foodEntries.indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            _foodEntries = [
              ..._foodEntries.sublist(0, idx),
              entry,
              ..._foodEntries.sublist(idx + 1),
            ];
          } else {
            _foodEntries = [..._foodEntries, entry];
          }
        }
      }

      _lastEntriesSync = DateTime.now().toUtc();
    } catch (_) {
      // Bei Fehler: Full-Fetch als Fallback
      await _loadEntries(date);
    }
  }

  /// Delta-Sync für Aktivitäten — identische Logik wie [_loadEntriesDelta].
  Future<void> _loadActivitiesDelta(DateTime date) async {
    if (_lastActivitiesSync == null) {
      await _loadActivities(date);
      return;
    }

    try {
      final svc = PhysicalActivityService(_db!);
      final stubs = await svc.getActivityStubs(date);

      final serverIds = {for (final s in stubs) s.id: s.updatedAt};
      final localIds = {for (final a in _activities) a.id};

      final deletedIds = localIds.difference(serverIds.keys.toSet());
      if (deletedIds.isNotEmpty) {
        _activities = _activities.where((a) => !deletedIds.contains(a.id)).toList();
      }

      final toFetch = stubs
          .where((s) =>
              !localIds.contains(s.id) ||
              s.updatedAt.isAfter(_lastActivitiesSync!))
          .map((s) => s.id)
          .toList();

      if (toFetch.isNotEmpty) {
        final updated = await svc.getActivitiesByIds(toFetch);
        for (final activity in updated) {
          final idx = _activities.indexWhere((a) => a.id == activity.id);
          if (idx >= 0) {
            _activities = [
              ..._activities.sublist(0, idx),
              activity,
              ..._activities.sublist(idx + 1),
            ];
          } else {
            _activities = [..._activities, activity];
          }
        }
      }

      _lastActivitiesSync = DateTime.now().toUtc();
    } catch (_) {
      await _loadActivities(date);
    }
  }
}
