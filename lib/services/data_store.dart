import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'food_entry_service.dart';
import 'physical_activity_service.dart';
import 'nutrition_goal_service.dart';
import 'water_intake_service.dart';
import 'serial_day_writer.dart';
import 'cheat_day_service.dart';
import 'streak_service.dart';
import 'neon_database_service.dart';
import 'local_data_service.dart';
import 'app_logger.dart';
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

  /// Canonical order for a day's food entries: the order they were logged in,
  /// oldest first.
  ///
  /// The list screen groups by meal type and then renders in list order without
  /// sorting, so whatever order this list happens to be in *is* the order the
  /// user sees. It used to depend on how the list came to be — a fresh load
  /// arrived newest-first from the query, while [addFoodEntry] and the delta
  /// sync appended — so a new entry sat at the bottom of its meal and jumped to
  /// the top after the next reload.
  ///
  /// Ascending is the direction that makes the optimistic append already
  /// correct, so nothing moves when the server copy arrives. Ties break on id:
  /// a meal template or a repeated meal inserts several entries at once and
  /// they can share a timestamp, and without a tiebreak their relative order
  /// would still wobble between loads.
  @visibleForTesting
  static int byLogOrder(FoodEntry a, FoodEntry b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  /// Every write to [_foodEntries] goes through here — sorting at the point of
  /// assignment rather than in the getter, which is read on every rebuild for
  /// the day's totals.
  void _setFoodEntries(Iterable<FoodEntry> entries) {
    _foodEntries = List<FoodEntry>.of(entries)..sort(byLogOrder);
  }

  List<PhysicalActivity> _activities = [];
  NutritionGoal? _goal;
  int _waterIntakeMl = 0;
  bool _isCheatDay = false;

  /// Name of the holiday the selected day belongs to, when it belongs to one.
  /// Null for a hand-toggled cheat day, an unnamed holiday, or a normal day.
  String? _holidayLabel;

  /// Holiday the selected day belongs to. Kept alongside [_holidayLabel] so the
  /// write-through cache can preserve the day's holiday membership.
  String? _holidayId;

  int _streak = 0;
  int _bestStreak = 0;
  List<int> _pendingMilestones = [];
  bool _isLoading = false;
  bool _isInitialLoading = true;

  /// True once a goal query has *authoritatively* completed — i.e. it either
  /// returned a row or confirmed there is none. The "no goal" empty state may
  /// only ever be shown when this is true. `_goal == null` on its own is
  /// ambiguous: it also means "not loaded yet" or "the fetch failed while the
  /// database was waking up", and must not trigger the empty state.
  bool _goalConfirmed = false;

  NeonDatabaseService? _db;
  LocalDataService? _local;

  /// Offline-mirror read/write cache for logged-in mode, keyed by the real user
  /// id. Distinct from [_local] (the guest-mode backend): when set, [_db] is
  /// also set. loadDay() hydrates from it instantly on cold start and writes
  /// each fetched day back through it. Attached via [attachCache].
  LocalDataService? _cache;

  // ── Delta-Sync Zeitstempel ─────────────────────────────────────────────────
  // Null = noch kein Sync für den aktuellen Tag → immer Full-Fetch.
  // Wird bei Tag-Wechsel (Full-Load) zurückgesetzt.
  DateTime? _lastEntriesSync;
  DateTime? _lastActivitiesSync;

  /// The day (y/m/d) for which an *authoritative server fetch* last completed.
  /// A cache hydrate does NOT set this — only a real reconcile does. The startup
  /// loader retries until this matches the selected day, so entries still load
  /// when the very first fetch was skipped because the token wasn't valid yet
  /// (common now that paint-first mounts Home before the token refresh lands).
  DateTime? _serverReconciledDate;

  /// The day currently held in memory — the last one [loadDay] was asked
  /// for, whether the fetch succeeded or not. Used to decide whether a
  /// late result still belongs to what the user is looking at.
  DateTime? _loadedDate;

  List<FoodEntry> get foodEntries => _foodEntries;

  /// The day's activities, newest first — matching the server query.
  ///
  /// Deliberately the opposite of [foodEntries], which reads oldest-first: a
  /// flat list of a day's activities is most useful with the latest at the top,
  /// while food entries are grouped by meal and read best in the order they
  /// were eaten. Both are stable; only the direction differs.
  ///
  /// Sorted here rather than trusted from the sources, because they disagree:
  /// the server orders by `start_time`, the local mirror ordered by
  /// `created_at` (so a cold start showed import order, not time of day), and
  /// [addActivity] appends to the end regardless. Which of those you saw
  /// depended on whether the server reconcile had landed yet, which is what
  /// made the order look arbitrary.
  List<PhysicalActivity> get activities =>
      [..._activities]..sort((a, b) => b.startTime.compareTo(a.startTime));
  NutritionGoal? get goal => _goal;
  int get waterIntakeMl => _waterIntakeMl;

  /// Computed water intake from liquid food entries and meals with liquid content
  /// Checks amountMl (set for both liquid foods and mixed meals with liquid ingredients)
  int get liquidFoodIntakeMl => _foodEntries
      .where((e) => e.amountMl != null)
      .fold(0, (sum, e) => sum + e.amountMl!.round());

  bool get isCheatDay => _isCheatDay;

  /// Holiday name for the selected day, or null when it is not a named
  /// holiday day. Only meaningful while [isCheatDay] is true.
  String? get holidayLabel => _holidayLabel;

  int get streak => _streak;
  int get bestStreak => _bestStreak;
  List<int> get pendingMilestones => List.unmodifiable(_pendingMilestones);
  bool get isLoading => _isLoading;

  /// True until the very first loadDay() call completes.
  bool get isInitialLoading => _isInitialLoading;

  /// Whether the goal state is authoritative — see [_goalConfirmed].
  /// The UI must gate the "no goal" empty state on this, never on `goal == null`.
  bool get goalConfirmed => _goalConfirmed;

  /// True when an authoritative server fetch has completed for [date] this
  /// session — i.e. entries/activities/goal reflect the backend, not just the
  /// local cache. See [_serverReconciledDate].
  bool serverReconciledFor(DateTime date) {
    final d = _serverReconciledDate;
    return d != null &&
        d.year == date.year &&
        d.month == date.month &&
        d.day == date.day;
  }

  void init(NeonDatabaseService db) {
    _db = db;
    // Drop any guest-mode local backend so loadDay() dispatches to the server.
    // The store is a process-lifetime singleton; on a guest→login transition it
    // otherwise keeps reading the (now-wiped) guest SQLite — which checks
    // _local before _db — until a full app restart. See initLocal().
    _local = null;
    // Re-attached per session in _initializeAndLoadData() once the user id
    // resolves; clear any stale cache from a previous session's login.
    _cache = null;
  }

  /// Attach a per-user local cache (offline mirror, logged-in mode). loadDay()
  /// then paints from it instantly on cold start and writes each fetched day
  /// back through it. The cache must already be init()'d with the real user id.
  void attachCache(LocalDataService cache) {
    _cache = cache;
  }

  /// Initialize for guest mode (local SQLite storage)
  void initLocal(LocalDataService local) {
    _local = local;
    // Guest and authenticated modes are mutually exclusive; keep exactly one
    // backend set so the loadDay() dispatch is unambiguous.
    _db = null;
    // The logged-in read-through cache only applies in authenticated mode.
    _cache = null;
  }

  /// Clear all in-memory state and arm the initial-loading flag.
  ///
  /// The store is a singleton, so without an explicit reset a previous
  /// session's `_isInitialLoading == false` and stale `_goal == null` would
  /// briefly leak into a fresh login — flashing the "no goal" screen before
  /// `loadDay()` finishes. Call this synchronously when a new session starts
  /// so the UI shows the loading indicator until real data arrives.
  void resetForNewSession() {
    _isInitialLoading = true;
    _isLoading = false;
    _goal = null;
    _goalConfirmed = false;
    _setFoodEntries(const []);
    _activities = [];
    _waterIntakeMl = 0;
    _isCheatDay = false;
    _holidayLabel = null;
    _holidayId = null;
    _streak = 0;
    _bestStreak = 0;
    _pendingMilestones = [];
    _lastEntriesSync = null;
    _lastActivitiesSync = null;
    _serverReconciledDate = null;
    _loadedDate = null;
    _waterWriter.clear();
    notifyListeners();
  }

  // ── Remote load ───────────────────────────────────────────────────────────

  /// Fetch data for [date] from the server or local database.
  ///
  /// [silent]  — kein Loading-Overlay (Hintergrund-Refresh).
  /// [delta]   — nur geänderte Records holen (ID-Set-Abgleich).
  ///             Setzt voraus dass [silent] true ist; wird von [_silentRefresh]
  ///             übergeben. Bei Tag-Wechsel immer false → Full-Fetch + Reset.
  Future<void> loadDay(DateTime date, {bool silent = false, bool delta = false}) async {
    // Guest mode or remote mode?
    if (_local == null && _db == null) return;
    _loadedDate = date;

    // ── Guest mode: local SQLite only ──
    if (_local != null) {
      if (!silent) {
        _isLoading = true;
        notifyListeners();
      }
      await Future.wait([
        _loadGoalLocal(date),
        _loadEntriesLocal(date),
        _loadActivitiesLocal(date),
        _loadWaterIntakeLocal(date),
        _loadCheatDayLocal(date),
      ]);
      _isLoading = false;
      _isInitialLoading = false;
      notifyListeners();
      return;
    }

    // ── Logged-in mode: local-first cache, then reconcile from the server ──
    // On the very first load, paint cached data instantly so a cold Neon
    // compute no longer blocks behind the full-screen spinner. The hydrate
    // clears _isInitialLoading when it finds a cached goal.
    final wasInitial = _isInitialLoading;
    if (!silent && wasInitial && _cache != null) {
      await _hydrateFromCache(date);
    }

    // Show the blocking loading indicator only when we still have nothing to
    // paint: a cache miss on the first load, or any later non-silent load
    // (day-change, jump-to-today). A successful hydrate skips it.
    final hydrated = wasInitial && !_isInitialLoading;
    if (!silent && !hydrated) {
      _isLoading = true;
      notifyListeners();
    }

    // Preflight: ohne userId und gültiges Token können wir keinen
    // authoritativen Fetch machen. In dem Fall lieber gar nichts ändern als
    // den im Speicher gehaltenen Zustand mit leeren Fallbacks zu überschreiben.
    // Sonst flackert beim Resume / nach Speichern eines Eintrags / während
    // einem Token-Refresh kurz der "kein Ziel konfiguriert"-Screen.
    final canFetch = _db!.userId != null &&
        await _db!.ensureValidToken(minMinutesValid: 5);

    if (!canFetch) {
      // Silent refresh (Resume, periodischer Refresh, nach-Speichern):
      // State unangetastet lassen, _isInitialLoading nicht umschalten.
      if (silent) return;
      // Initialer/expliziter Load: Loading-Flag freigeben, damit der Spinner
      // verschwindet — aber den restlichen State nicht clobbern. (Ein Cache-
      // Hydrate hat _isInitialLoading ggf. schon gelöscht und Daten gemalt.)
      _isLoading = false;
      _isInitialLoading = false;
      notifyListeners();
      return;
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

    // Persist the freshly-fetched day into the cache so the next cold start is
    // instant. Best-effort; never blocks or fails the load.
    if (_cache != null) {
      await _writeThroughToCache(date);
    }

    // Reached only when canFetch was true, so this day now reflects the server.
    _serverReconciledDate = date;
    _isLoading = false;
    _isInitialLoading = false;
    notifyListeners();
  }

  // ── Offline-mirror cache helpers (logged-in) ────────────────────────────────

  /// Fast read of [date] from the local cache to paint the UI before the server
  /// responds. A cached goal is enough to render the app, so finding one clears
  /// the loading gate immediately; without one we keep waiting for the server
  /// (mirrors [_goalConfirmed] — never show the "no goal" state from a cache
  /// miss). Best-effort: any failure just falls through to the normal fetch.
  Future<void> _hydrateFromCache(DateTime date) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final goal = await cache.getGoalForDate(date);
      final entries = await cache.getFoodEntriesForDate(date);
      final activities = await cache.getActivitiesForDate(date);
      final water = await cache.getWaterIntakeForDate(date);
      final cheat = await cache.getCheatDay(date);

      _setFoodEntries(entries);
      _activities = activities;
      _waterIntakeMl = water;
      _applyCheatDay(cheat);
      if (goal != null) {
        _goal = goal;
        _goalConfirmed = true;
        _isInitialLoading = false;
        notifyListeners(); // paint cached data immediately
      }
    } catch (e) {
      appLogger.w('⚠️ Cache hydrate failed: $e');
    }
  }

  /// Persists the current in-memory day (already reconciled from the server)
  /// into the local cache under the real user id, so the next cold start can
  /// hydrate from it. Best-effort; failures are logged and ignored.
  Future<void> _writeThroughToCache(DateTime date) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      if (_goal != null) await cache.upsertGoal(_goal!);
      await cache.replaceCachedEntriesForDate(date, _foodEntries);
      await cache.replaceCachedActivitiesForDate(date, _activities);
      await cache.setWaterIntakeForDate(date, _waterIntakeMl);
      if (_isCheatDay) {
        // Pass the holiday through: without it, mirroring a day fetched from
        // the server would drop its holiday membership locally and the banner
        // would lose the name on the next cold start.
        await cache.markCheatDay(date,
            note: _holidayLabel, holidayId: _holidayId);
      } else {
        await cache.unmarkCheatDay(date);
      }
    } catch (e) {
      appLogger.w('⚠️ Cache write-through failed: $e');
    }
  }

  /// Background-caches the trailing [days] days of food entries + activities so
  /// past-day browsing is instant/offline and the cache stays warm. Best-effort
  /// and fire-and-forget — call after the initial load. No-op without a cache/db
  /// or a valid token.
  Future<void> backfillRecentDays({int days = 30}) async {
    final cache = _cache;
    final db = _db;
    if (cache == null || db == null) return;
    if (db.userId == null || !await db.ensureValidToken(minMinutesValid: 5)) {
      return;
    }
    try {
      final today = DateTime.now();
      final end = DateTime(today.year, today.month, today.day);
      final start = end.subtract(Duration(days: days));

      final entries =
          await FoodEntryService(db).getFoodEntriesForRange(start, end);
      final activities = await PhysicalActivityService(db)
          .getActivitiesInRange(start: start, end: end);

      String dayKey(DateTime d) => d.toIso8601String().split('T')[0];
      final entriesByDay = <String, List<FoodEntry>>{};
      for (final e in entries) {
        (entriesByDay[dayKey(e.entryDate)] ??= []).add(e);
      }
      final actsByDay = <String, List<PhysicalActivity>>{};
      for (final a in activities) {
        (actsByDay[dayKey(a.startTime)] ??= []).add(a);
      }

      // Only write days that actually have server data — an empty day is left
      // untouched (it will reconcile if the user opens it).
      final touchedDays = {...entriesByDay.keys, ...actsByDay.keys};
      for (final key in touchedDays) {
        final date = DateTime.parse(key);
        await cache.replaceCachedEntriesForDate(
            date, entriesByDay[key] ?? const []);
        await cache.replaceCachedActivitiesForDate(
            date, actsByDay[key] ?? const []);
      }
      appLogger.i('✅ Backfilled ${touchedDays.length} days into local cache');
    } catch (e) {
      appLogger.w('⚠️ Cache backfill failed: $e');
    }
  }

  // ── Food entries ──────────────────────────────────────────────────────────

  void addFoodEntry(FoodEntry entry) {
    _setFoodEntries([..._foodEntries, entry]);
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
    _setFoodEntries(_foodEntries.map((e) => e.id == entry.id ? entry : e));
    notifyListeners();
  }

  void removeFoodEntry(String id) {
    _setFoodEntries(_foodEntries.where((e) => e.id != id));
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
    // A directly supplied goal (e.g. just saved on the profile screen) is an
    // authoritative result. A null clear is not — leave _goalConfirmed alone
    // so a give-up path can't promote the "no goal" screen.
    if (goal != null) _goalConfirmed = true;
    notifyListeners();
  }

  // ── Water ─────────────────────────────────────────────────────────────────

  /// Applies [deltaMl] to the day's water intake and persists the result.
  ///
  /// The in-memory value moves immediately so the counter reacts to the tap,
  /// and the write goes through [_waterWriter]: one request at a time, last
  /// value wins. Two quick taps therefore always leave the backend on the
  /// value the user saw, and until the write is acknowledged a refresh is
  /// stopped from painting the older server value over it.
  Future<void> adjustWaterIntake(DateTime date, int deltaMl) async {
    final baseline = _waterIntakeMl;
    _waterIntakeMl = (baseline + deltaMl).clamp(0, 9999);
    notifyListeners();
    await _waterWriter.submit(date, _waterIntakeMl, baseline: baseline);
  }

  late final SerialDayWriter _waterWriter = SerialDayWriter(
    write: _writeWaterIntake,
    onFailure: _revertWaterIntake,
  );

  /// Persists one water value. Returns false only when the backend rejected
  /// the write, which sends the displayed value back to where the burst began.
  Future<bool> _writeWaterIntake(DateTime date, int amountMl) async {
    final local = _local;
    if (local != null) {
      try {
        await local.setWaterIntakeForDate(date, amountMl);
        return true;
      } catch (e) {
        appLogger.e('❌ Local water write failed: $e');
        return false;
      }
    }
    final db = _db;
    // No backend attached yet — keep the optimistic value rather than snapping
    // it back; the next load reconciles it.
    if (db == null) return true;
    final saved = await WaterIntakeService(db).setIntakeForDate(date, amountMl);
    if (saved == null) return false;
    // Mirror into the offline cache right away, so returning to the day (or a
    // cold start) hydrates the new value instead of the last reconciled one.
    try {
      await _cache?.setWaterIntakeForDate(date, amountMl);
    } catch (e) {
      appLogger.w('⚠️ Water cache write failed: $e');
    }
    return true;
  }

  /// Undoes the optimistic update of a burst the backend refused — but only
  /// while that day is still the one on screen.
  void _revertWaterIntake(DateTime date, int baseline) {
    final loaded = _loadedDate;
    if (loaded == null) return;
    if (loaded.year != date.year ||
        loaded.month != date.month ||
        loaded.day != date.day) {
      return;
    }
    _waterIntakeMl = baseline;
    notifyListeners();
  }

  // ── Cheat day ─────────────────────────────────────────────────────────────

  /// Optimistic per-day toggle from the overview chip.
  ///
  /// Always clears the holiday info, which matches what the toggle does on the
  /// server: un-marking deletes the row, so the day leaves its holiday, and
  /// re-marking creates a plain day that belongs to none. (On the error-revert
  /// path a holiday day briefly loses its name until the next load — harmless,
  /// and better than showing a holiday for a day that just left one.)
  void setCheatDay(bool value) {
    _isCheatDay = value;
    _holidayLabel = null;
    _holidayId = null;
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

  // Hinweis zu allen Loadern unten: Bei einer Exception NICHT den im Speicher
  // gehaltenen Wert überschreiben. Sonst clobbert ein transienter Fehler
  // (Token-Race, Netzwerk-Hiccup) sichtbaren State — z.B. flackert der
  // "kein Ziel konfiguriert"-Screen, oder Wasserstand fällt kurz auf 0.

  Future<void> _loadGoal(DateTime date) async {
    try {
      _goal = await NutritionGoalService(_db!).getGoalForDateStrict(date);
      // Query erfolgreich (Zeile ODER authoritativ keine) → Zustand ist sicher.
      _goalConfirmed = true;
    } catch (_) {
      // Fetch fehlgeschlagen → bestehendes Goal beibehalten und NICHT als
      // bestätigt markieren. Sonst erschiene der "kein Ziel"-Screen, obwohl
      // wir den echten Zustand (noch) nicht kennen — z.B. während die DB
      // aufwacht oder ein Token-Refresh läuft.
    }
  }

  Future<void> _loadEntries(DateTime date) async {
    try {
      _setFoodEntries(await FoodEntryService(_db!).getFoodEntriesForDate(date));
      _lastEntriesSync = DateTime.now().toUtc();
    } catch (_) {
      // Bestehende Einträge beibehalten — nicht auf [] setzen.
    }
  }

  Future<void> _loadActivities(DateTime date) async {
    try {
      _activities = await PhysicalActivityService(_db!).getActivitiesForDate(date);
      _lastActivitiesSync = DateTime.now().toUtc();
    } catch (_) {
      // Bestehende Aktivitäten beibehalten.
    }
  }

  Future<void> _loadWaterIntake(DateTime date) async {
    try {
      final fetched = await WaterIntakeService(_db!).getIntakeForDate(date);
      // A tap the server hasn't acknowledged yet would be answered with the
      // value it replaced — dropping the user's change back to the old one.
      if (_waterWriter.hasPending(date)) return;
      _waterIntakeMl = fetched;
    } catch (_) {
      // Bestehenden Wasserstand beibehalten.
    }
  }

  Future<void> _loadCheatDay(DateTime date) async {
    try {
      _applyCheatDay(await CheatDayService(_db!).getCheatDay(date));
    } catch (_) {
      // Bestehenden Cheat-Day-Status beibehalten.
    }
  }

  /// Applies a cheat day row (or its absence) to the in-memory day state.
  void _applyCheatDay(CheatDay? day) {
    _isCheatDay = day != null;
    _holidayId = day?.holidayId;
    _holidayLabel = day?.holidayLabel;
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
      // Bestehenden Streak beibehalten.
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
        _setFoodEntries(_foodEntries.where((e) => !deletedIds.contains(e.id)));
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
          // Replace in place or add; _setFoodEntries re-establishes the
          // order either way, so a changed createdAt cannot strand an entry.
          final idx = _foodEntries.indexWhere((e) => e.id == entry.id);
          _setFoodEntries([
            if (idx >= 0) ..._foodEntries.sublist(0, idx) else ..._foodEntries,
            entry,
            if (idx >= 0) ..._foodEntries.sublist(idx + 1),
          ]);
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

  // ── Local mode loaders (SQLite) ───────────────────────────────────────────

  /// Load nutrition goal from local SQLite
  Future<void> _loadGoalLocal(DateTime date) async {
    try {
      _goal = await _local!.getGoalForDate(date);
      // Local SQLite is always reachable → this result is authoritative.
      _goalConfirmed = true;
    } catch (e) {
      appLogger.e('❌ Error loading goal locally: $e');
      _goal = null;
    }
  }

  /// Load food entries from local SQLite
  Future<void> _loadEntriesLocal(DateTime date) async {
    try {
      _setFoodEntries(await _local!.getFoodEntriesForDate(date));
      _lastEntriesSync = DateTime.now().toUtc();
    } catch (e) {
      appLogger.e('❌ Error loading entries locally: $e');
      _setFoodEntries(const []);
    }
  }

  /// Load activities from local SQLite
  Future<void> _loadActivitiesLocal(DateTime date) async {
    try {
      _activities = await _local!.getActivitiesForDate(date);
      _lastActivitiesSync = DateTime.now().toUtc();
    } catch (e) {
      appLogger.e('❌ Error loading activities locally: $e');
      _activities = [];
    }
  }

  /// Load water intake from local SQLite
  Future<void> _loadWaterIntakeLocal(DateTime date) async {
    try {
      final fetched = await _local!.getWaterIntakeForDate(date);
      if (_waterWriter.hasPending(date)) return; // see [_loadWaterIntake]
      _waterIntakeMl = fetched;
    } catch (e) {
      appLogger.e('❌ Error loading water intake locally: $e');
      _waterIntakeMl = 0;
    }
  }

  /// Load cheat day from local SQLite
  Future<void> _loadCheatDayLocal(DateTime date) async {
    try {
      _applyCheatDay(await _local!.getCheatDay(date));
    } catch (e) {
      appLogger.e('❌ Error loading cheat day locally: $e');
      _applyCheatDay(null);
    }
  }
}
