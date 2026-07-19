import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../models/food_entry.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
import '../models/food_shortcut.dart';
import '../models/models.dart' show NutritionGoal;
import '../services/food_database_service.dart';
import '../services/food_shortcuts_service.dart';
import '../services/barcode_lookup_service.dart';
import '../services/neon_database_service.dart';
import '../services/user_food_prefs_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import 'barcode_scanner_sheet.dart';
import 'repeat_meal_picker.dart';
import '../screens/add_food_entry_screen.dart' show createFoodFromScannedBarcode;

/// Postgres rejects an empty string as a `uuid`, and PostgREST surfaces
/// that as a 400 which [SyncService.createFoodEntry] misreads as
/// "offline" — so the entry gets queued, the red bar latches on, and
/// every replay hits the same error.
///
/// In particular [OpenFoodFactsService] constructs barcode-lookup
/// [FoodItem]s with `id: ''` because OFF results aren't persisted to
/// our food_database until later. Normalize blank ids to null so the
/// JSON serializer drops the `food_id` field entirely.
String? _nonEmptyFoodId(String? raw) =>
    (raw == null || raw.trim().isEmpty) ? null : raw;

/// Vereinheitlichtes Bottom-Sheet zum Hinzufügen von Einträgen — der einzige
/// Einstiegspunkt auf dem Einträge-Tab.
///
/// Enthält:
///   • Suchfeld   – Live-Suche in der Lebensmittel-Datenbank
///   • Barcode    – Scan-Button im Suchfeld
///   • Zuletzt    – kürzlich eingetragene Lebensmittel (1 Tipp = sofort loggen)
///   • Favoriten  – Lebensmittel mit is_favourite=true aus food_database
///   • Kurzbefehle– nutzerkonfigurierte Einzel-Einträge (SharedPreferences)
///   • Buttons    – Mahlzeiten-Vorlagen (Cloud) und manuelle Eingabe
class QuickFoodEntrySheet extends StatefulWidget {
  final NeonDatabaseService dbService;
  final DateTime date;
  final MealType initialMealType;

  /// Callback: erhält einen vollständig gefüllten [FoodEntry] (inkl. UUID).
  /// Der Aufrufer ist für Persistenz + DataStore-Update zuständig.
  final Future<void> Function(FoodEntry) onAdd;

  /// Öffnet die Mahlzeiten-Vorlagen (Cloud-Edition). Null = nicht verfügbar;
  /// dann wird der Vorlagen-Button ausgeblendet.
  final VoidCallback? onOpenTemplates;

  /// Öffnet das vollständige Eingabe-Formular für die manuelle Erfassung.
  final VoidCallback onManualEntry;

  /// Opens the "describe your meal" free-text flow. Null hides the button
  /// (e.g. guest mode, where fuzzy DB search isn't available).
  final VoidCallback? onDescribeMeal;

  /// Startet den Nährwertetikett-Scan (Cloud-Edition, mobil). Null = nicht
  /// verfügbar; dann wird der Etikett-Scan-Button ausgeblendet.
  final VoidCallback? onScanLabel;

  /// Opens the food-database management screen (edit / delete custom
  /// foods). Null hides the header button — e.g. in guest mode where
  /// there's no remote database to manage.
  final VoidCallback? onManageDatabase;

  /// Daily macro goal active for [date], used to drive macro-gap
  /// suggestions. When null the sheet falls back to phase-1/2/3 ranking
  /// only — no gap hint is rendered.
  final NutritionGoal? dailyGoal;

  /// Macros already logged for [date] at the moment the sheet opens. The
  /// sheet tracks deltas internally for each add, so callers don't need
  /// to push updates while it's open.
  final double initialConsumedCalories;
  final double initialConsumedProtein;
  final double initialConsumedFat;
  final double initialConsumedCarbs;

  const QuickFoodEntrySheet({
    super.key,
    required this.dbService,
    required this.date,
    required this.initialMealType,
    required this.onAdd,
    required this.onManualEntry,
    this.onDescribeMeal,
    this.onOpenTemplates,
    this.onScanLabel,
    this.onManageDatabase,
    this.dailyGoal,
    this.initialConsumedCalories = 0,
    this.initialConsumedProtein = 0,
    this.initialConsumedFat = 0,
    this.initialConsumedCarbs = 0,
  });

  @override
  State<QuickFoodEntrySheet> createState() => _QuickFoodEntrySheetState();
}

class _QuickFoodEntrySheetState extends State<QuickFoodEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MealType _mealType;

  /// Raw recent fetch (last 90 days, ordered by created_at desc) before
  /// dedup. Kept raw so the time-of-day re-ranking in [_displayRecent] can
  /// re-evaluate when the user picks a different meal-type chip without
  /// re-hitting the network. Also drives the co-occurrence index.
  List<FoodEntry> _rawRecent = [];
  List<FoodItem> _favouriteFoods = [];
  List<FoodShortcut> _shortcuts = [];
  Map<String, FoodItem> _recentFoods = {};
  bool _loading = true;
  String? _addingId;

  /// Cached per-user portion presets keyed by food id. Populated as foods
  /// surface in the sheet (favourites, recent, search) and consulted by
  /// [_pickFood] to override the food's generic serving size with the
  /// user's typical portion.
  final Map<String, UserFoodPref> _portionPrefs = {};

  /// Name of the most recently logged entry — drives the in-sheet "added"
  /// toast. Null while no toast is showing.
  String? _lastAddedName;
  Timer? _toastTimer;

  /// Built once per [_loadRecent] over the 90-day window. Null until the
  /// initial fetch completes.
  _CooccurrenceIndex? _cooccurrence;

  /// Distinct-date counts per `(name, mealType, weekday)`. Drives the
  /// "you always log this on Mondays at breakfast" promotion in
  /// [_rankAndDedupRecent].
  _RecurrenceIndex? _recurrence;

  /// Current suggestion chip row contents. Refreshed after every successful
  /// add (keyed off the just-added entry) and cleared on context changes
  /// (meal-type chip, search start).
  List<FoodEntry> _suggestions = const [];

  /// Names logged since the sheet opened — excluded from suggestions so we
  /// never recommend something the user already added in this session.
  final Set<String> _loggedThisSession = <String>{};

  /// Running totals for the active day. Initialized from
  /// [QuickFoodEntrySheet.initialConsumed*] and incremented on each add
  /// so phase-4 macro-gap suggestions stay accurate without the parent
  /// having to push updates.
  late double _consumedCalories;
  late double _consumedProtein;
  late double _consumedFat;
  late double _consumedCarbs;

  /// Phase-4 macro-gap suggestions — recomputed when the index loads and
  /// after each successful add. Renders in the shared chip slot only
  /// when [_suggestions] (Phase 2) is empty.
  List<FoodEntry> _macroGapSuggestions = const [];

  /// Macro the [_macroGapSuggestions] are filling. Drives the chip-row
  /// header text ("Short on protein"). Null when no gap is active.
  _MacroKind? _macroGapKind;

  // ── Live-Suche ───────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<FoodItem> _searchResults = [];
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mealType = widget.initialMealType;
    _consumedCalories = widget.initialConsumedCalories;
    _consumedProtein = widget.initialConsumedProtein;
    _consumedFat = widget.initialConsumedFat;
    _consumedCarbs = widget.initialConsumedCarbs;
    // Wake a possibly-sleeping Neon compute now, while the user is still reading
    // the sheet, so the first food search doesn't pay the cold-start latency.
    // Fire-and-forget; the searchFoods retry still covers a miss.
    widget.dbService.warmUp();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadRecent(), _loadFavourites(), _loadShortcuts()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRecent() async {
    final db = widget.dbService;
    final tokenValid = await db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) return;
    final userId = db.userId;
    if (userId == null) return;

    final end = DateTime.now();
    // 90 days gives the co-occurrence index enough signal to fire
    // minSupport ≥ 2 pairs without re-fetching at suggestion time.
    final start = end.subtract(const Duration(days: 90));
    final endStr = end.toIso8601String().split('T')[0];
    final startStr = start.toIso8601String().split('T')[0];

    try {
      final response = await db.client
          .from('food_entries')
          .select()
          .eq('user_id', userId)
          .gte('entry_date', startStr)
          .lte('entry_date', endStr)
          .order('created_at', ascending: false)
          .limit(1000);

      final entries = (response as List)
          .map((json) => FoodEntry.fromJson(json as Map<String, dynamic>))
          .toList();

      // Preload food items for the initially-displayed set. The display set
      // can shift on meal-type change but recent entries don't churn much,
      // so the cache stays mostly accurate without re-fetching.
      final initialDisplay =
          _rankAndDedupRecent(entries, _mealType, DateTime.now().hour);
      final foodService = FoodDatabaseService(widget.dbService);
      final uniqueFoodIds = initialDisplay
          .where((e) => e.foodId != null)
          .map((e) => e.foodId!)
          .toSet();
      final foodFutures = uniqueFoodIds
          .map((id) => foodService.getFoodById(id))
          .toList();
      final loadedFoods = await Future.wait(foodFutures);
      final recentFoods = <String, FoodItem>{};
      for (int i = 0; i < uniqueFoodIds.length; i++) {
        final food = loadedFoods[i];
        if (food != null) {
          recentFoods[uniqueFoodIds.elementAt(i)] = food;
        }
      }

      final index = _CooccurrenceIndex.build(entries);
      final recurrence = _RecurrenceIndex.build(entries);

      if (mounted) {
        setState(() {
          _rawRecent = entries;
          _recentFoods = recentFoods;
          _cooccurrence = index;
          _recurrence = recurrence;
          _refreshMacroGapSuggestions();
        });
      }
      await _prefetchPortionPrefs(uniqueFoodIds);
    } catch (_) {}
  }

  /// Picks the macro whose remaining fraction-of-goal is largest. Returns
  /// null when no macro is short by more than [_macroGapMinFraction], the
  /// daily goal isn't available, or the user hasn't eaten enough today
  /// yet (the "of course you're short, you just woke up" silencer).
  _MacroKind? _dominantGap() {
    final goal = widget.dailyGoal;
    if (goal == null) return null;
    // Calorie-based "have you started eating yet" gate. Skipped for
    // macro-only goals where calories aren't tracked.
    if (goal.calories > 0 &&
        _consumedCalories < goal.calories * _macroGapMinDayProgress) {
      return null;
    }

    double frac(double goalVal, double consumed) {
      if (goalVal <= 0) return 0;
      final remaining = goalVal - consumed;
      return remaining <= 0 ? 0 : remaining / goalVal;
    }

    final pP = frac(goal.protein, _consumedProtein);
    // Protein-only mode: fat & carbs have no target, so only nudge on protein.
    if (goal.proteinOnlyEffective) {
      return pP >= _macroGapMinFraction ? _MacroKind.protein : null;
    }
    final pF = frac(goal.fat, _consumedFat);
    final pC = frac(goal.carbs, _consumedCarbs);
    final best = [
      (_MacroKind.protein, pP),
      (_MacroKind.fat, pF),
      (_MacroKind.carbs, pC),
    ].reduce((a, b) => a.$2 >= b.$2 ? a : b);
    return best.$2 >= _macroGapMinFraction ? best.$1 : null;
  }

  /// Recomputes [_macroGapSuggestions] for the current consumption state.
  /// Caller is responsible for wrapping in setState.
  void _refreshMacroGapSuggestions() {
    final kind = _dominantGap();
    if (kind == null) {
      _macroGapKind = null;
      _macroGapSuggestions = const [];
      return;
    }

    double macroOf(FoodEntry e) {
      switch (kind) {
        case _MacroKind.protein:
          return e.protein;
        case _MacroKind.fat:
          return e.fat;
        case _MacroKind.carbs:
          return e.carbs;
      }
    }

    final seen = <String>{};
    final candidates = <FoodEntry>[];
    // _rawRecent is ordered by created_at desc, so within the same name
    // the first hit is the most recent — a fine template for re-logging.
    for (final e in _rawRecent) {
      final name = e.name.toLowerCase().trim();
      if (name.isEmpty) continue;
      if (_loggedThisSession.contains(name)) continue;
      if (macroOf(e) < _macroGapMinGrams) continue;
      if (!seen.add(name)) continue;
      candidates.add(e);
    }
    candidates.sort((a, b) => macroOf(b).compareTo(macroOf(a)));
    _macroGapKind = kind;
    _macroGapSuggestions = candidates.take(3).toList();
  }

  /// Returns up to 3 [FoodEntry] templates the user often logs alongside
  /// [seedName] in the same meal session. Excludes the seed and anything
  /// already logged during this sheet session. Empty when the index hasn't
  /// loaded or no pair clears the minSupport threshold.
  List<FoodEntry> _computeSuggestions(String seedName) {
    final idx = _cooccurrence;
    if (idx == null) return const [];
    final exclude = <String>{
      ..._loggedThisSession,
      seedName.toLowerCase().trim(),
    };
    final names = idx.suggest(seedName, k: 3, exclude: exclude);
    final result = <FoodEntry>[];
    for (final name in names) {
      FoodEntry? best;
      for (final e in _rawRecent) {
        if (e.name.toLowerCase().trim() != name) continue;
        if (best == null || e.createdAt.isAfter(best.createdAt)) best = e;
      }
      if (best != null) result.add(best);
    }
    return result;
  }

  /// Sorts [_rawRecent] by relevance to the current meal context, then
  /// dedupes by lowercase name. Recomputed on every rebuild so changing
  /// the meal-type chip immediately re-ranks the list.
  ///
  /// Uses `widget.date.weekday` (not "today") so back-filling a past meal
  /// still benefits from that weekday's recurrence pattern.
  List<FoodEntry> _displayRecent() => _rankAndDedupRecent(
        _rawRecent,
        _mealType,
        DateTime.now().hour,
        _recurrence,
        widget.date.weekday,
      );

  Future<void> _loadFavourites() async {
    try {
      final foods =
          await FoodDatabaseService(widget.dbService).getFavouriteFoods();
      if (mounted) setState(() => _favouriteFoods = foods);
      await _prefetchPortionPrefs(foods.map((f) => f.id));
    } catch (_) {}
  }

  /// Batch-loads portion presets for [foodIds] and merges them into the
  /// in-memory cache. Already-cached ids are skipped, so repeated calls
  /// (favourites + recent + search) don't re-query rows we already have.
  Future<void> _prefetchPortionPrefs(Iterable<String> foodIds) async {
    final missing = foodIds
        .where((id) => id.isNotEmpty && !_portionPrefs.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    final prefs = await UserFoodPrefsService(widget.dbService)
        .getForFoodIds(missing);
    if (!mounted || prefs.isEmpty) return;
    setState(() => _portionPrefs.addAll(prefs));
  }

  /// Toggles the favourite flag for [food]. Optimistically flips the star in
  /// search results; on success re-fetches the Favorites tab so its ordering
  /// stays in sync with the database. Rolls back search highlight on failure.
  Future<void> _toggleFavourite(FoodItem food) async {
    final newValue = !food.isFavourite;
    setState(() {
      _searchResults = _searchResults
          .map((f) =>
              f.id == food.id ? f.copyWith(isFavourite: newValue) : f)
          .toList();
    });
    try {
      await FoodDatabaseService(widget.dbService)
          .toggleFoodFavourite(food.id, isFavourite: newValue);
      await _loadFavourites();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = _searchResults
            .map((f) =>
                f.id == food.id ? f.copyWith(isFavourite: !newValue) : f)
            .toList();
      });
    }
  }

  Future<void> _loadShortcuts() async {
    final list = await FoodShortcutsService.loadShortcuts();
    if (mounted) setState(() => _shortcuts = list);
  }

  // ── add helpers ──────────────────────────────────────────────────────────────

  Future<void> _addEntry(FoodEntry entry, double? amountG) async {
    if (_addingId != null) return;
    setState(() => _addingId = entry.id);
    try {
      await widget.onAdd(entry);

      // Remember this portion for next time. Only foods that live in our
      // food_database (foodId set) get a pref row — OFF/USDA hits and
      // meal-template entries don't have a stable food id to key against.
      final prefFoodId = entry.foodId;
      if (prefFoodId != null && prefFoodId.isNotEmpty && !entry.isMeal) {
        _portionPrefs[prefFoodId] =
            UserFoodPref(amount: entry.amount, unit: entry.unit);
        unawaited(UserFoodPrefsService(widget.dbService).upsert(
          foodId: prefFoodId,
          amount: entry.amount,
          unit: entry.unit,
        ));
      }

      // Copy cloud micronutrients for database-backed foods (best-effort).
      // Needs the grams the entry represents; skipped when unknown.
      if (amountG != null &&
          !entry.isMeal &&
          entry.foodId != null &&
          entry.foodId!.isNotEmpty) {
        final jwt = widget.dbService.jwt;
        final userId = widget.dbService.userId;
        if (jwt != null && userId != null) {
          premiumFeatures.copyFoodMicrosToEntry(
            foodId: entry.foodId!,
            entryId: entry.id,
            userId: userId,
            amountG: amountG,
            authToken: jwt,
            apiUrl: NeonDatabaseService.dataApiUrl,
          );
        }
      }

      if (mounted) {
        HapticFeedback.lightImpact();
        _toastTimer?.cancel();
        _loggedThisSession.add(entry.name.toLowerCase().trim());
        _consumedCalories += entry.calories;
        _consumedProtein += entry.protein;
        _consumedFat += entry.fat;
        _consumedCarbs += entry.carbs;
        final nextSuggestions = _computeSuggestions(entry.name);
        setState(() {
          _lastAddedName = entry.name;
          _suggestions = nextSuggestions;
          _refreshMacroGapSuggestions();
        });
        _toastTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _lastAddedName = null);
        });
        // SnackBar acts as a fallback for the brief window where the user
        // dismisses the sheet before the in-sheet toast renders — under
        // the sheet it's hidden, but it's already on the queue.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.foodAdded(entry.name)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ));
      }
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  // ── Suche ────────────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _searching = true;
      // Search takes focus; the suggestion strip would be hidden behind
      // the results anyway.
      _suggestions = const [];
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (q.isEmpty) return;
    try {
      final results =
          await FoodDatabaseService(widget.dbService).searchFoods(q, limit: 40);
      // Ignore stale responses — the query moved on while we were waiting.
      if (!mounted || q != _query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
      await _prefetchPortionPrefs(results.map((f) => f.id));
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _searchResults = [];
      _searching = false;
    });
  }

  // ── Barcode ──────────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    final barcode = await showBarcodeScannerSheet(context);
    if (barcode == null || !mounted) return;

    final locale = Localizations.localeOf(context).languageCode;

    // Blocking loader — covers both the OFF/local lookup and (on OFF hit)
    // the silent save into the user's own food DB. Single overlay so the
    // user doesn't see "nothing happening" between the two awaits.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    BarcodeLookupResult? result;
    FoodItem? foodForEntry;
    try {
      result = await BarcodeLookupService.lookup(
        barcode,
        dbService: FoodDatabaseService(widget.dbService),
        locale: locale,
      );
      // On OFF hit: persist the food to the user's own DB so the next scan
      // of this barcode resolves locally (no OFF round-trip). No portions
      // — those get added later via the food database screen when the
      // user actually has portion knowledge to attach.
      if (result != null && result.fromOff) {
        try {
          final created = await FoodDatabaseService(widget.dbService)
              .createFood(result.food.copyWith(barcode: barcode));
          if (result.micros.isNotEmpty) {
            final jwt = widget.dbService.jwt;
            final userId = widget.dbService.userId;
            if (jwt != null && userId != null) {
              await premiumFeatures.saveFoodDatabaseMicrosFromMap(
                foodId: created.id,
                userId: userId,
                micros100g: result.micros,
                authToken: jwt,
                apiUrl: NeonDatabaseService.dataApiUrl,
              );
            }
          }
          foodForEntry = created;
        } catch (e) {
          // Silent — the entry still logs from the OFF row, the save can
          // be retried via the food database screen.
          appLogger.w('⚠️ Silent OFF→own save failed: $e');
        }
      }
    } finally {
      if (mounted) Navigator.of(context).pop(); // dismiss the loader
    }
    if (!mounted) return;

    if (result == null) {
      // Nothing matched. Offer to create a new food carrying this barcode
      // (nutrition entered manually or scanned from the label); on save we log
      // an entry for it just like a normal scan hit.
      final created = await createFoodFromScannedBarcode(
        context: context,
        dbService: widget.dbService,
        barcode: barcode,
      );
      if (created != null && mounted) {
        await _pickFood(created);
      }
      return;
    }
    await _pickFood(foodForEntry ?? result.food);
  }

  // ── Auswahl eines Datenbank-Lebensmittels (Favoriten, Suche, Scan) ───────────

  /// Opens the confirm dialog for a [food] from food_database (per-100g values),
  /// then logs it on confirm.
  Future<void> _pickFood(FoodItem food) async {
    // Prefer the user's remembered portion (last_amount + last_unit from
    // user_food_prefs) when one exists for this food — falls back to the
    // food's generic servingSize otherwise. The pref is stored as a flat
    // amount + unit pair, so we only apply it when the unit matches what
    // the confirm dialog can scale against (food's serving unit, 'g', or
    // 'ml'); other units (named portions) are surfaced verbatim and we
    // let _confirm do its scaling from the food's per-100g table.
    final pref = _portionPrefs[food.id];
    // No remembered portion → default to the food's primary (first) named
    // portion when it has one, so e.g. "1 slice" is preselected instead of
    // a raw gram serving size. Falls back to servingSize, then 100 g.
    final primaryPortion =
        food.portions.isNotEmpty ? food.portions.first : null;
    final double defaultAmount;
    final String defaultUnit;
    final double defaultGrams; // grams the default selection represents
    if (pref != null) {
      defaultAmount = pref.amount;
      defaultUnit = pref.unit;
      defaultGrams = defaultAmount;
    } else if (primaryPortion != null) {
      defaultAmount = 1;
      defaultUnit = primaryPortion.name;
      defaultGrams = primaryPortion.amountG;
    } else {
      defaultAmount = food.servingSize ?? 100.0;
      defaultUnit = food.servingUnit ?? 'g';
      defaultGrams = defaultAmount;
    }
    final f = defaultGrams / 100;
    final confirmed = await _confirm(
      name: food.name,
      amount: defaultAmount,
      unit: defaultUnit,
      calories: food.calories * f,
      protein: food.protein * f,
      fat: food.fat * f,
      carbs: food.carbs * f,
      fiber: food.fiber != null ? food.fiber! * f : null,
      sugar: food.sugar != null ? food.sugar! * f : null,
      sodium: food.sodium != null ? food.sodium! * f : null,
      saturatedFat: food.saturatedFat != null ? food.saturatedFat! * f : null,
      foodId: _nonEmptyFoodId(food.id),
      scaleByAmount: true,
      isLiquid: food.isLiquid,
      amountMl: food.isLiquid ? defaultGrams : null,
      isMeal: false,
      food: food,
    );
    if (confirmed != null) {
      await _addEntry(confirmed.entry, confirmed.amountG);
    }
  }

  // ── Zuletzt-Eintrag: 1 Tipp = sofort loggen, Langtipp = anpassen ─────────────

  /// Re-logs [recent] immediately with its stored amount/nutrition, using the
  /// meal type currently selected in the sheet.
  Future<void> _instantAddRecent(FoodEntry recent) async {
    final entry = FoodEntry(
      id: const Uuid().v4(),
      userId: widget.dbService.userId!,
      foodId: _nonEmptyFoodId(recent.foodId),
      mealTemplateId: recent.mealTemplateId,
      entryDate: widget.date,
      mealType: _mealType,
      name: recent.name,
      amount: recent.amount,
      unit: recent.unit,
      calories: recent.calories,
      protein: recent.protein,
      fat: recent.fat,
      carbs: recent.carbs,
      fiber: recent.fiber,
      sugar: recent.sugar,
      sodium: recent.sodium,
      saturatedFat: recent.saturatedFat,
      isLiquid: recent.isLiquid,
      amountMl: recent.amountMl,
      isMeal: recent.isMeal,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final amountG =
        (recent.unit == 'g' || recent.unit == 'ml') ? recent.amount : null;
    await _addEntry(entry, amountG);
  }

  /// Single repeat suggestion for the currently selected meal-type chip,
  /// or null when nothing applies. Prefers yesterday's same meal-type;
  /// falls back to the leftover-pattern cross-meal hint when there's
  /// nothing from yesterday at the same meal — "lunch ← yesterday's
  /// dinner" and "dinner ← today's lunch". Capped at one to keep the
  /// row from crowding the Recent list below.
  ({String label, List<FoodEntry> sources})? _repeatSuggestion(
      AppLocalizations l) {
    final yesterday = widget.date.subtract(const Duration(days: 1));

    List<FoodEntry> entriesFor(DateTime day, MealType mt) => _rawRecent
        .where((e) =>
            DateUtils.isSameDay(e.entryDate, day) && e.mealType == mt)
        .toList();

    final sameMeal = entriesFor(yesterday, _mealType);
    if (sameMeal.isNotEmpty) {
      return (
        label: l.repeatYesterdaysMeal(_mealType.localizedName(l)),
        sources: sameMeal,
      );
    }

    if (_mealType == MealType.lunch) {
      final ydDinner = entriesFor(yesterday, MealType.dinner);
      if (ydDinner.isNotEmpty) {
        return (
          label: l.repeatYesterdaysMeal(MealType.dinner.localizedName(l)),
          sources: ydDinner,
        );
      }
    } else if (_mealType == MealType.dinner) {
      final todayLunch = entriesFor(widget.date, MealType.lunch);
      if (todayLunch.isNotEmpty) {
        return (
          label: l.repeatTodaysMeal(MealType.lunch.localizedName(l)),
          sources: todayLunch,
        );
      }
    }

    return null;
  }

  /// Bulk-logs every source entry into [widget.date] under the current
  /// meal-type. Calls [widget.onAdd] directly (bypassing the per-entry
  /// snackbar path in [_addEntry]) so the user gets one combined toast at
  /// the end instead of N stacked snackbars. [label] is shown in that
  /// toast so the user knows which suggestion fired.
  Future<void> _repeatMealFromSuggestion(
      String label, List<FoodEntry> sources) async {
    if (_addingId != null || sources.isEmpty) return;

    // More than one item → let the user pick which to repeat; a single-item
    // meal repeats directly (unchanged behaviour).
    var entries = sources;
    if (entries.length > 1) {
      final picked = await showRepeatMealPicker(
        context,
        label: label,
        entries: entries,
        macroOnly: widget.dailyGoal?.macroOnly == true,
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      entries = picked;
    }

    setState(() => _addingId = 'repeat-meal');
    try {
      for (final src in entries) {
        final entry = FoodEntry(
          id: const Uuid().v4(),
          userId: widget.dbService.userId!,
          foodId: _nonEmptyFoodId(src.foodId),
          mealTemplateId: src.mealTemplateId,
          entryDate: widget.date,
          mealType: _mealType,
          name: src.name,
          amount: src.amount,
          unit: src.unit,
          calories: src.calories,
          protein: src.protein,
          fat: src.fat,
          carbs: src.carbs,
          fiber: src.fiber,
          sugar: src.sugar,
          sodium: src.sodium,
          saturatedFat: src.saturatedFat,
          isLiquid: src.isLiquid,
          amountMl: src.amountMl,
          isMeal: src.isMeal,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await widget.onAdd(entry);
        _consumedCalories += entry.calories;
        _consumedProtein += entry.protein;
        _consumedFat += entry.fat;
        _consumedCarbs += entry.carbs;
        _loggedThisSession.add(entry.name.toLowerCase().trim());
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label · ${entries.length}'),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        duration: const Duration(seconds: 2),
      ));
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  /// Opens the confirm dialog pre-filled from [entry] so the amount/meal can be
  /// tweaked before logging — the long-press path on a Recent item.
  Future<void> _adjustRecent(FoodEntry entry) async {
    final food = entry.foodId != null ? _recentFoods[entry.foodId] : null;
    final confirmed = await _confirm(
      name: entry.name,
      amount: entry.amount,
      unit: entry.unit,
      calories: entry.calories,
      protein: entry.protein,
      fat: entry.fat,
      carbs: entry.carbs,
      fiber: entry.fiber,
      sugar: entry.sugar,
      sodium: entry.sodium,
      saturatedFat: entry.saturatedFat,
      foodId: _nonEmptyFoodId(entry.foodId),
      scaleByAmount: food != null,
      food: food,
      isLiquid: entry.isLiquid,
      amountMl: entry.amountMl,
      isMeal: entry.isMeal,
      recentEntry: entry,
    );
    if (confirmed != null) {
      await _addEntry(confirmed.entry, confirmed.amountG);
    }
  }

  FoodEntry _entryFromShortcut(FoodShortcut sc) {
    final userId = widget.dbService.userId!;
    return FoodEntry(
      id: const Uuid().v4(),
      userId: userId,
      foodId: _nonEmptyFoodId(sc.foodId),
      entryDate: widget.date,
      mealType: MealType.fromJson(sc.mealType),
      name: sc.label,
      amount: sc.amount,
      unit: sc.unit,
      calories: sc.calories,
      protein: sc.protein,
      fat: sc.fat,
      carbs: sc.carbs,
      fiber: sc.fiber,
      sugar: sc.sugar,
      sodium: sc.sodium,
      saturatedFat: sc.saturatedFat,
      isLiquid: sc.isLiquid,
      amountMl: sc.amountMl,
      isMeal: sc.isMeal,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // ── confirm dialog ────────────────────────────────────────────────────────────

  /// Returns the confirmed entry plus the grams it represents (null when the
  /// unit is an unresolvable portion), or null if cancelled.
  Future<({FoodEntry entry, double? amountG})?> _confirm({
    required String name,
    required double amount,
    required String unit,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    double? fiber,
    double? sugar,
    double? sodium,
    double? saturatedFat,
    String? foodId,
    bool scaleByAmount = false, // true for food_database items (per-100g values)
    FoodItem? food,
    FoodEntry? recentEntry,
    bool isLiquid = false,
    double? amountMl,
    bool isMeal = false,
  }) {
    return showDialog<({FoodEntry entry, double? amountG})>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        name: name,
        initialAmount: amount,
        unit: unit,
        mealType: _mealType,
        calories: calories,
        protein: protein,
        fat: fat,
        carbs: carbs,
        fiber: fiber,
        sugar: sugar,
        sodium: sodium,
        saturatedFat: saturatedFat,
        foodId: foodId,
        scaleByAmount: scaleByAmount,
        food: food,
        recentEntry: recentEntry,
        isLiquid: isLiquid,
        amountMl: amountMl,
        isMeal: isMeal,
        userId: widget.dbService.userId!,
        date: widget.date,
        onMealTypeChanged: (mt) => setState(() => _mealType = mt),
        onSaveAsShortcut: _saveAsShortcut,
      ),
    );
  }

  Future<void> _saveAsShortcut({
    required String label,
    required String? foodId,
    required String mealType,
    required double amount,
    required String unit,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    double? fiber,
    double? sugar,
    double? sodium,
    double? saturatedFat,
    bool isLiquid = false,
    double? amountMl,
    bool isMeal = false,
  }) async {
    final sc = FoodShortcut(
      id: const Uuid().v4(),
      label: label,
      foodId: foodId,
      mealType: mealType,
      amount: amount,
      unit: unit,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      saturatedFat: saturatedFat,
      isLiquid: isLiquid,
      amountMl: amountMl,
      isMeal: isMeal,
    );
    await FoodShortcutsService.addShortcut(sc);
    await _loadShortcuts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.shortcutSaved(label)),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.add_circle, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.add,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (widget.onDescribeMeal != null)
                IconButton(
                  icon: const Icon(Icons.record_voice_over),
                  tooltip: l.describeMealTitle,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDescribeMeal!();
                  },
                ),
              if (widget.onManageDatabase != null)
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: l.myFoods,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onManageDatabase!();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // Meal-type chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: MealType.values
                .map((mt) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${mt.icon} ${mt.localizedName(l)}',
                            style: const TextStyle(fontSize: 12)),
                        selected: _mealType == mt,
                        onSelected: (v) {
                          if (v) {
                            setState(() {
                              _mealType = mt;
                              // Meal context changed; suggestions tied to
                              // the previous bucket no longer apply.
                              _suggestions = const [];
                            });
                          }
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
        // Search field with an inline barcode-scan button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l.searchFoodHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l.clearSearch,
                      visualDensity: VisualDensity.compact,
                      onPressed: _clearSearch,
                    ),
                  if (widget.onScanLabel != null)
                    IconButton(
                      icon: const Icon(Icons.document_scanner),
                      tooltip: l.scanNutritionLabel,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onScanLabel!();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: l.barcodeScanTitle,
                    visualDensity: VisualDensity.compact,
                    onPressed: _scan,
                  ),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        // Content: live search results while a query is entered,
        // browse tabs (Recent / Favourites / Shortcuts) otherwise.
        Expanded(
          child: Stack(
            children: [
              _query.isEmpty ? _buildBrowse() : _buildSearchResults(),
              // In-sheet "added" confirmation. Overlaid on the bottom of the
              // list (not in the column flow) so showing/hiding it never
              // shifts the rows the user is rapidly tapping. Lives inside the
              // 85%-tall sheet because a ScaffoldMessenger SnackBar would be
              // occluded by it. IgnorePointer lets taps fall through to the
              // list rows it briefly covers.
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _lastAddedName == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_lastAddedName),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                                child: _AddedToast(name: _lastAddedName!)),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowse() {
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        // Quick links: meal templates (Cloud) + manual entry form
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              if (widget.onOpenTemplates != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restaurant_menu, size: 18),
                    label: Text(l.templates,
                        style: const TextStyle(fontSize: 13)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenTemplates!();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(l.manualEntry,
                      style: const TextStyle(fontSize: 13)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onManualEntry();
                  },
                ),
              ),
            ],
          ),
        ),
        // Shared suggestion strip. Phase 2 (co-occurrence after add) wins;
        // Phase 4 (macro-gap) fills the slot when Phase 2 is empty.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _suggestions.isNotEmpty
              ? _SuggestionsRow(
                  suggestions: _suggestions,
                  addingId: _addingId,
                  onTap: _instantAddRecent,
                )
              : (_macroGapSuggestions.isNotEmpty && _macroGapKind != null
                  ? _MacroGapRow(
                      suggestions: _macroGapSuggestions,
                      kind: _macroGapKind!,
                      addingId: _addingId,
                      onTap: _instantAddRecent,
                    )
                  : const SizedBox(width: double.infinity)),
        ),
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabRecent),
            Tab(text: l.tabFavorites),
            Tab(text: l.tabShortcuts),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RecentTab(
                entries: _displayRecent(),
                addingId: _addingId,
                onTap: _instantAddRecent,
                onLongPress: _adjustRecent,
                suggestion:
                    _repeatSuggestion(AppLocalizations.of(context)!),
                onRepeatSuggestion: _repeatMealFromSuggestion,
                macroOnly: widget.dailyGoal?.macroOnly == true,
              ),
              _FavouritesTab(
                foods: _favouriteFoods,
                addingId: _addingId,
                onTap: _pickFood,
                onToggleFavourite: _toggleFavourite,
                macroOnly: widget.dailyGoal?.macroOnly == true,
              ),
              _ShortcutsTab(
                shortcuts: _shortcuts,
                addingId: _addingId,
                macroOnly: widget.dailyGoal?.macroOnly == true,
                onTap: (sc) async {
                  final entry = _entryFromShortcut(sc);
                  // Grams known only for g/ml shortcuts; portion
                  // shortcuts don't store the portion weight.
                  final amountG = (sc.unit == 'g' || sc.unit == 'ml')
                      ? sc.amount
                      : null;
                  await _addEntry(entry, amountG);
                },
                onDelete: (sc) async {
                  await FoodShortcutsService.removeShortcut(sc.id);
                  await _loadShortcuts();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final l = AppLocalizations.of(context)!;
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.noSearchResults(_query),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final food = _searchResults[i];
        final isAdding = _addingId == food.id;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            child:
                const Icon(Icons.restaurant, color: Colors.blue, size: 20),
          ),
          title: Text(food.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            _macroSummary(l, l.per100g, food.calories, food.protein,
                food.fat, food.carbs,
                macroOnly: widget.dailyGoal?.macroOnly == true),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        food.isFavourite ? Icons.star : Icons.star_border,
                        color: food.isFavourite
                            ? Colors.amber.shade600
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                      onPressed: () => _toggleFavourite(food),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.add_circle_outline, color: Colors.teal),
                  ],
                ),
          onTap: isAdding ? null : () => _pickFood(food),
        );
      },
    );
  }
}

/// Compact one-line macro summary, e.g. "100 g · 250 kcal · P12 F8 K30".
/// [base] is an already-formatted prefix — a serving size or "per 100 g".
/// When [macroOnly] is true the kcal segment is dropped so calorie-free
/// tracking stays calorie-free on the logging surface.
String _macroSummary(AppLocalizations l, String base, double kcal,
    double protein, double fat, double carbs,
    {bool macroOnly = false}) {
  final macros = '${l.macroProteinShort}${protein.toStringAsFixed(0)} '
      '${l.macroFatShort}${fat.toStringAsFixed(0)} '
      '${l.macroCarbsShort}${carbs.toStringAsFixed(0)}';
  if (macroOnly) return '$base · $macros';
  return '$base · ${kcal.toStringAsFixed(0)} kcal · $macros';
}

// ── Recent ranking ────────────────────────────────────────────────────────────

/// Minimum distinct-date count for a `(name, mealType, weekday)` slot to
/// count as a recurring habit. With a 90-day window each weekday occurs
/// ~13 times, so 4 hits = ≥30% of matching slots — conservative enough to
/// avoid false positives from a brief streak.
const int _recurrenceThreshold = 4;

/// Circular hour distance, 0–12. e.g. distance(23, 1) == 2.
int _hourDistance(int a, int b) {
  final d = (a - b).abs();
  return d > 12 ? 24 - d : d;
}

/// Lower is better. Sort order:
///   1. Recurrent items (`(name, mealType, weekday)` count ≥ threshold)
///      win, with higher counts beating lower counts within the group.
///   2. Items whose stored `mealType` matches the active selection win.
///   3. Hour-of-day distance to "now".
///   4. Recency.
///
/// The recurrence boost is what lifts a "every Monday-breakfast oatmeal"
/// to the top even on weeks where the user happened to log other things
/// more recently.
int _compareRecent(
  FoodEntry a,
  FoodEntry b,
  MealType mealType,
  int hour,
  _RecurrenceIndex? recurrence,
  int weekday,
) {
  if (recurrence != null) {
    final aRec = recurrence.count(a.name, mealType, weekday);
    final bRec = recurrence.count(b.name, mealType, weekday);
    final aIsRec = aRec >= _recurrenceThreshold;
    final bIsRec = bRec >= _recurrenceThreshold;
    if (aIsRec != bIsRec) return aIsRec ? -1 : 1;
    if (aIsRec && bIsRec && aRec != bRec) return bRec - aRec;
  }

  final aMatch = a.mealType == mealType ? 0 : 1;
  final bMatch = b.mealType == mealType ? 0 : 1;
  if (aMatch != bMatch) return aMatch - bMatch;

  final aHourDist = _hourDistance(a.createdAt.hour, hour);
  final bHourDist = _hourDistance(b.createdAt.hour, hour);
  if (aHourDist != bHourDist) return aHourDist - bHourDist;

  return b.createdAt.compareTo(a.createdAt);
}

/// Sorts [entries] by relevance to the current ([mealType], [hour], [weekday])
/// context, then dedupes by lowercase name, keeping the best-ranked entry
/// per name. [recurrence] is optional — when null, ranking falls through
/// to the phase-1 heuristic.
List<FoodEntry> _rankAndDedupRecent(
  List<FoodEntry> entries,
  MealType mealType,
  int hour, [
  _RecurrenceIndex? recurrence,
  int weekday = 0,
]) {
  final sorted = entries.toList()
    ..sort(
      (a, b) => _compareRecent(a, b, mealType, hour, recurrence, weekday),
    );
  final seen = <String>{};
  final result = <FoodEntry>[];
  for (final e in sorted) {
    if (seen.add(e.name.toLowerCase().trim()) && result.length < 30) {
      result.add(e);
    }
  }
  return result;
}

// ── Macro-gap awareness ───────────────────────────────────────────────────────

/// Macros tracked for gap detection. Calories are intentionally excluded —
/// they're a derived total, not an independent macro to "fill".
enum _MacroKind { protein, fat, carbs }

/// Don't suggest macro fills unless the dominant macro is still short by
/// at least this fraction of its daily goal. Keeps the strip silent in
/// the morning (everything is "missing" then) and at end-of-day (when
/// the user has already hit their numbers).
const double _macroGapMinFraction = 0.30;

/// Don't surface a candidate that contributes less than this many grams
/// of the deficit macro — sub-gram amounts feel noisy and would push
/// out genuinely useful items.
const double _macroGapMinGrams = 5.0;

/// Don't fire macro-gap suggestions until the user has consumed at least
/// this fraction of their daily calorie target. Silences the "of course
/// I'm short, I just woke up" case at the first meal. Bypassed for
/// macro-only goals where calories aren't tracked.
const double _macroGapMinDayProgress = 0.25;

// ── Recurrence index ──────────────────────────────────────────────────────────

/// Counts how many distinct dates a food appears in for each
/// `(name, mealType, weekday)` slot, over the same 90-day fetch as
/// [_CooccurrenceIndex].
///
/// Drives the "every Monday-breakfast oatmeal" promotion in
/// [_compareRecent]. Distinct-date counting (rather than raw entry count)
/// prevents a single date with duplicate entries from inflating the
/// score.
class _RecurrenceIndex {
  /// Composite key `"$name|$mealType|$weekday"` → distinct entry-dates.
  final Map<String, int> _counts;

  _RecurrenceIndex._(this._counts);

  factory _RecurrenceIndex.build(List<FoodEntry> entries) {
    // Track which (date, mealType, name) triples we've already counted so
    // a duplicate within the same meal doesn't double-count the day.
    final seenTriple = <String>{};
    final counts = <String, int>{};
    for (final e in entries) {
      final name = e.name.toLowerCase().trim();
      if (name.isEmpty) continue;
      final dateStr = e.entryDate.toIso8601String().split('T')[0];
      final mt = e.mealType.toJson();
      final tripleKey = '$dateStr|$mt|$name';
      if (!seenTriple.add(tripleKey)) continue;
      final slotKey = '$name|$mt|${e.entryDate.weekday}';
      counts[slotKey] = (counts[slotKey] ?? 0) + 1;
    }
    return _RecurrenceIndex._(counts);
  }

  /// Distinct-date count for [name] in the `(mealType, weekday)` slot.
  int count(String name, MealType mealType, int weekday) {
    final key =
        '${name.toLowerCase().trim()}|${mealType.toJson()}|$weekday';
    return _counts[key] ?? 0;
  }
}

// ── Co-occurrence index ───────────────────────────────────────────────────────

/// Counts how often pairs of distinct food names appear in the same
/// `(entry_date, mealType)` meal session, then ranks neighbours of a given
/// name by conditional probability `P(B|A) = co[A][B] / occ[A]`.
///
/// Built once per [_QuickFoodEntrySheetState._loadRecent] over the 90-day
/// fetch — cheap enough to live entirely in memory.
class _CooccurrenceIndex {
  /// Lowercased name → number of meal buckets the name appeared in.
  final Map<String, int> _occ;

  /// Lowercased name A → lowercased name B → number of meal buckets in
  /// which both A and B appeared. Symmetric: `_co[A][B] == _co[B][A]`.
  final Map<String, Map<String, int>> _co;

  _CooccurrenceIndex._(this._occ, this._co);

  factory _CooccurrenceIndex.build(List<FoodEntry> entries) {
    final buckets = <String, Set<String>>{};
    for (final e in entries) {
      final dateStr = e.entryDate.toIso8601String().split('T')[0];
      final key = '$dateStr|${e.mealType.toJson()}';
      final name = e.name.toLowerCase().trim();
      if (name.isEmpty) continue;
      (buckets[key] ??= <String>{}).add(name);
    }
    final occ = <String, int>{};
    final co = <String, Map<String, int>>{};
    for (final names in buckets.values) {
      for (final n in names) {
        occ[n] = (occ[n] ?? 0) + 1;
      }
      final list = names.toList();
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i];
          final b = list[j];
          (co[a] ??= <String, int>{})[b] = (co[a]![b] ?? 0) + 1;
          (co[b] ??= <String, int>{})[a] = (co[b]![a] ?? 0) + 1;
        }
      }
    }
    return _CooccurrenceIndex._(occ, co);
  }

  /// Top-[k] lowercased names that co-occur with [name], ranked by
  /// `P(B|A) = co[A][B] / occ[A]` with at least [minSupport] joint
  /// observations. Names in [exclude] are skipped.
  List<String> suggest(String name,
      {int k = 3, int minSupport = 2, Set<String> exclude = const {}}) {
    final a = name.toLowerCase().trim();
    final occA = _occ[a] ?? 0;
    if (occA == 0) return const [];
    final neighbours = _co[a];
    if (neighbours == null) return const [];
    final scored = <MapEntry<String, double>>[];
    for (final entry in neighbours.entries) {
      if (entry.value < minSupport) continue;
      if (exclude.contains(entry.key)) continue;
      scored.add(MapEntry(entry.key, entry.value / occA));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(k).map((e) => e.key).toList();
  }
}

// ── Suggestion chip row ───────────────────────────────────────────────────────

class _SuggestionsRow extends StatelessWidget {
  final List<FoodEntry> suggestions;
  final String? addingId;
  final void Function(FoodEntry) onTap;

  const _SuggestionsRow({
    required this.suggestions,
    required this.addingId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.deepPurple.shade50,
      child: Row(
        children: [
          const Icon(Icons.auto_awesome,
              size: 14, color: Colors.deepPurple),
          const SizedBox(width: 6),
          Text(
            l.suggestionsHint,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in suggestions) ...[
                    ActionChip(
                      avatar: addingId == e.id
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 16),
                      label: Text(e.name,
                          style: const TextStyle(fontSize: 12)),
                      onPressed:
                          addingId == e.id ? null : () => onTap(e),
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Macro-gap chip row ────────────────────────────────────────────────────────

class _MacroGapRow extends StatelessWidget {
  final List<FoodEntry> suggestions;
  final _MacroKind kind;
  final String? addingId;
  final void Function(FoodEntry) onTap;

  const _MacroGapRow({
    required this.suggestions,
    required this.kind,
    required this.addingId,
    required this.onTap,
  });

  String _headerText(AppLocalizations l) {
    switch (kind) {
      case _MacroKind.protein:
        return l.shortOnProtein;
      case _MacroKind.fat:
        return l.shortOnFat;
      case _MacroKind.carbs:
        return l.shortOnCarbs;
    }
  }

  double _macroOf(FoodEntry e) {
    switch (kind) {
      case _MacroKind.protein:
        return e.protein;
      case _MacroKind.fat:
        return e.fat;
      case _MacroKind.carbs:
        return e.carbs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          const Icon(Icons.flag, size: 14, color: Colors.deepOrange),
          const SizedBox(width: 6),
          Text(
            _headerText(l),
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in suggestions) ...[
                    ActionChip(
                      avatar: addingId == e.id
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 16),
                      label: Text(
                        '${e.name} · ${_macroOf(e).toStringAsFixed(0)}g',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed:
                          addingId == e.id ? null : () => onTap(e),
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Added toast ───────────────────────────────────────────────────────────────

class _AddedToast extends StatelessWidget {
  final String name;
  const _AddedToast({required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.green.shade600,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.foodAdded(name),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent tab ────────────────────────────────────────────────────────────────

class _RecentTab extends StatelessWidget {
  final List<FoodEntry> entries;
  final String? addingId;

  /// One tap → log immediately with the stored amount.
  final void Function(FoodEntry) onTap;

  /// Long press → open the confirm dialog to adjust amount/meal first.
  final void Function(FoodEntry) onLongPress;

  /// Single repeat suggestion, or null when nothing applies for the
  /// currently selected meal-type. Renders as one compact bar above
  /// the orange recent-hint banner.
  final ({String label, List<FoodEntry> sources})? suggestion;
  final Future<void> Function(String label, List<FoodEntry> sources)
      onRepeatSuggestion;

  /// Hide the kcal segment in macro summaries when in macro-only mode.
  final bool macroOnly;

  const _RecentTab({
    required this.entries,
    required this.addingId,
    required this.onTap,
    required this.onLongPress,
    required this.suggestion,
    required this.onRepeatSuggestion,
    this.macroOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final s = suggestion;
    if (entries.isEmpty && s == null) {
      return Center(
        child: Text(l.noRecentEntries,
            style: const TextStyle(color: Colors.grey)),
      );
    }
    final isRepeating = addingId == 'repeat-meal';
    return Column(
      children: [
        if (s != null)
          _RepeatSuggestionRow(
            label: s.label,
            sources: s.sources,
            isRepeating: isRepeating,
            onTap: () => onRepeatSuggestion(s.label, s.sources),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.orange.shade50,
          child: Text(
            l.recentTapHint,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: entries.length,
            itemBuilder: (ctx, i) {
              final e = entries[i];
              final isAdding = addingId == e.id;
              final eCount = e.amount;
              final eCountStr = eCount == eCount.truncateToDouble()
                  ? eCount.toInt().toString()
                  : eCount.toStringAsFixed(1);
              final amountStr = e.unit == 'g' || e.unit == 'ml'
                  ? '${e.amount.toStringAsFixed(0)}${e.unit}'
                  : e.unit == 'Portion'
                      ? '$eCountStr ${eCount == 1.0 ? l.portion : l.portions}'
                      : '$eCountStr × ${e.unit}';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: const Icon(Icons.history,
                      color: Colors.orange, size: 20),
                ),
                title: Text(e.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  _macroSummary(l, amountStr, e.calories, e.protein,
                      e.fat, e.carbs, macroOnly: macroOnly),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: isAdding
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline,
                        color: Colors.teal),
                onTap: isAdding ? null : () => onTap(e),
                onLongPress: isAdding ? null : () => onLongPress(e),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Repeat suggestion row ─────────────────────────────────────────────────────

/// Compact one-line "Repeat …" bar pinned at the top of the Recent tab.
/// Dense by design — the Recent list below is the primary surface, so this
/// bar yields most of the vertical space. Theme-aware (secondaryContainer /
/// onSecondaryContainer) so contrast holds in light and dark mode.
class _RepeatSuggestionRow extends StatelessWidget {
  final String label;
  final List<FoodEntry> sources;
  final bool isRepeating;
  final VoidCallback onTap;

  const _RepeatSuggestionRow({
    required this.label,
    required this.sources,
    required this.isRepeating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: InkWell(
        onTap: isRepeating ? null : onTap,
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom:
                  BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              isRepeating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(cs.onSecondaryContainer)))
                  : Icon(Icons.replay,
                      color: cs.onSecondaryContainer, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$label · ${sources.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                  size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Favourites tab ────────────────────────────────────────────────────────────

class _FavouritesTab extends StatelessWidget {
  final List<FoodItem> foods;
  final String? addingId;
  final void Function(FoodItem) onTap;
  final void Function(FoodItem) onToggleFavourite;
  final bool macroOnly;

  const _FavouritesTab({
    required this.foods,
    required this.addingId,
    required this.onTap,
    required this.onToggleFavourite,
    this.macroOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (foods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.noFavorites,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: foods.length,
      itemBuilder: (ctx, i) {
        final food = foods[i];
        final isAdding = addingId == food.id;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.amber.shade50,
            child: const Icon(Icons.star, color: Colors.amber, size: 20),
          ),
          title: Text(food.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            _macroSummary(l, l.per100g, food.calories, food.protein,
                food.fat, food.carbs, macroOnly: macroOnly),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.star,
                          color: Colors.amber.shade600, size: 22),
                      onPressed: () => onToggleFavourite(food),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.add_circle_outline, color: Colors.teal),
                  ],
                ),
          onTap: isAdding ? null : () => onTap(food),
        );
      },
    );
  }
}

// ── Shortcuts tab ─────────────────────────────────────────────────────────────

class _ShortcutsTab extends StatelessWidget {
  final List<FoodShortcut> shortcuts;
  final String? addingId;
  final void Function(FoodShortcut) onTap;
  final void Function(FoodShortcut) onDelete;
  final bool macroOnly;

  const _ShortcutsTab({
    required this.shortcuts,
    required this.addingId,
    required this.onTap,
    required this.onDelete,
    this.macroOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (shortcuts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.noShortcuts,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: shortcuts.length,
      itemBuilder: (ctx, i) {
        final sc = shortcuts[i];
        final isAdding = addingId == sc.id;
        final mealIcon = _mealIcon(sc.mealType);
        return Dismissible(
          key: Key(sc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => onDelete(sc),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.shade50,
              child: Text(mealIcon, style: const TextStyle(fontSize: 18)),
            ),
            title: Text(sc.label, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              _macroSummary(l, '${sc.amount.toStringAsFixed(0)} ${sc.unit}',
                  sc.calories, sc.protein, sc.fat, sc.carbs,
                  macroOnly: macroOnly),
              style: const TextStyle(fontSize: 11),
            ),
            trailing: isAdding
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt, color: Colors.orange),
            onTap: isAdding ? null : () => onTap(sc),
          ),
        );
      },
    );
  }

  String _mealIcon(String mealType) {
    switch (mealType) {
      case 'breakfast':
        return '🌅';
      case 'lunch':
        return '☀️';
      case 'dinner':
        return '🌙';
      default:
        return '🍎';
    }
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatefulWidget {
  final String name;
  final double initialAmount;
  final String unit;
  final MealType mealType;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;
  final double? saturatedFat;
  final String? foodId;

  /// If true, all nutrition values are scaled proportionally when amount changes.
  final bool scaleByAmount;

  /// Non-null when the source is a food_database item (provides per-100g values).
  final FoodItem? food;

  /// Non-null when the source is a recent entry.
  final FoodEntry? recentEntry;

  /// Whether this is a liquid food
  final bool isLiquid;

  /// For liquid foods: the ml amount
  final double? amountMl;

  /// Whether this is a meal entry (totals) or food entry (per-100g scaled)
  final bool isMeal;

  final String userId;
  final DateTime date;
  final void Function(MealType) onMealTypeChanged;
  final Future<void> Function({
    required String label,
    required String? foodId,
    required String mealType,
    required double amount,
    required String unit,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    double? fiber,
    double? sugar,
    double? sodium,
    double? saturatedFat,
    bool isLiquid,
    double? amountMl,
    bool isMeal,
  }) onSaveAsShortcut;

  const _ConfirmDialog({
    required this.name,
    required this.initialAmount,
    required this.unit,
    required this.mealType,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    this.saturatedFat,
    this.foodId,
    required this.scaleByAmount,
    this.food,
    this.recentEntry,
    required this.isLiquid,
    this.amountMl,
    required this.isMeal,
    required this.userId,
    required this.date,
    required this.onMealTypeChanged,
    required this.onSaveAsShortcut,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late TextEditingController _amountCtrl;
  late MealType _mealType;
  late String _selectedUnit;
  FoodPortion? _selectedPortion;
  bool _savingShortcut = false;

  // Auto-derived uncertainty (weighed g/ml → exact, named portion → rougher,
  // seeded by the food's own level). Re-derived on unit change until the user
  // overrides it via the picker.
  late EstimateLevel _estimateLevel;
  bool _userSetEstimate = false;

  /// Auto default for the current selection.
  EstimateLevel _autoEstimate() => EstimateLevel.defaultForLog(
        foodLevel: widget.food?.estimateLevel ?? EstimateLevel.none,
      );

  double get _currentAmount =>
      tryParseDouble(_amountCtrl.text) ?? widget.initialAmount;

  bool get _isGramMl => _selectedUnit == 'g' || _selectedUnit == 'ml';

  /// Grams the current selection represents — null when the unit is a
  /// portion that can't be resolved to a gram weight.
  double? _currentAmountG() {
    final amount = _currentAmount;
    if (_isGramMl) return amount;
    if (_selectedPortion != null) return amount * _selectedPortion!.amountG;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.initialAmount.toStringAsFixed(0));
    _mealType = widget.mealType;
    _selectedUnit = widget.unit;
    // Check if the unit matches a named portion
    if (widget.food != null) {
      _selectedPortion = widget.food!.portions.cast<FoodPortion?>().firstWhere(
            (p) => p!.name == widget.unit,
            orElse: () => null,
          );
    }
    _estimateLevel = _autoEstimate();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  List<String> _availableUnits() {
    final food = widget.food;
    if (food == null) return [widget.unit]; // No switching without food
    final units = <String>[];
    for (final p in food.portions) {
      units.add(p.name);
    }
    units.add('g');
    if (food.isLiquid || widget.unit == 'ml') {
      units.add('ml');
    }
    // The stored unit may no longer match a portion (renamed/removed) — keep
    // it selectable so the DropdownButton always has a valid current value.
    if (!units.contains(_selectedUnit)) {
      units.insert(0, _selectedUnit);
    }
    return units;
  }

  void _onUnitChanged(String unit) {
    final food = widget.food;
    setState(() {
      _selectedUnit = unit;
      _selectedPortion = food?.portions.cast<FoodPortion?>().firstWhere(
            (p) => p!.name == unit,
            orElse: () => null,
          );
      // Reset amount: 1 for named portions, servingSize or 100 for g/ml
      if (_selectedPortion != null) {
        _amountCtrl.text = '1';
      } else if (unit == 'g' || unit == 'ml') {
        final servingSize = food?.servingSize ?? 100.0;
        _amountCtrl.text = servingSize.toStringAsFixed(0);
      }
      // Follow the portion type unless the user has explicitly overridden.
      if (!_userSetEstimate) _estimateLevel = _autoEstimate();
    });
  }

  FoodEntry _buildEntry() {
    final amount = _currentAmount;
    final scale =
        widget.initialAmount != 0 ? amount / widget.initialAmount : 1.0;
    final food = widget.food;
    final re = widget.recentEntry;

    double calories, protein, fat, carbs;
    double? fiber, sugar, sodium, saturatedFat, scaledAmountMl;
    String unitToStore = _selectedUnit;

    // Per-100g scaling only when grams are known: g/ml unit, or a portion
    // that resolved against the food. Otherwise fall through to ratio scaling
    // so a "2 pieces" entry is never mistaken for "2 grams".
    if (food != null && (_selectedPortion != null || _isGramMl)) {
      // Calculate grams from selected unit
      final grams = _selectedPortion != null
          ? amount * _selectedPortion!.amountG // named portion → grams
          : amount; // g or ml directly
      final f = grams / 100.0;
      calories = food.calories * f;
      protein = food.protein * f;
      fat = food.fat * f;
      carbs = food.carbs * f;
      fiber = food.fiber != null ? food.fiber! * f : null;
      sugar = food.sugar != null ? food.sugar! * f : null;
      sodium = food.sodium != null ? food.sodium! * f : null;
      saturatedFat = food.saturatedFat != null ? food.saturatedFat! * f : null;
      if (food.isLiquid) {
        scaledAmountMl = grams; // grams ≈ ml for liquids
      }
    } else if (re != null) {
      // No food item: scale stored totals by ratio (unit can't change)
      calories = re.calories * scale;
      protein = re.protein * scale;
      fat = re.fat * scale;
      carbs = re.carbs * scale;
      fiber = re.fiber != null ? re.fiber! * scale : null;
      sugar = re.sugar != null ? re.sugar! * scale : null;
      sodium = re.sodium != null ? re.sodium! * scale : null;
      saturatedFat = re.saturatedFat != null ? re.saturatedFat! * scale : null;
      if (widget.isLiquid && widget.amountMl != null) {
        scaledAmountMl = widget.amountMl! * scale;
      }
    } else {
      final f = widget.scaleByAmount ? amount / 100.0 : scale;
      calories = widget.calories * f;
      protein = widget.protein * f;
      fat = widget.fat * f;
      carbs = widget.carbs * f;
      fiber = widget.fiber != null ? widget.fiber! * f : null;
      sugar = widget.sugar != null ? widget.sugar! * f : null;
      sodium = widget.sodium != null ? widget.sodium! * f : null;
      saturatedFat = widget.saturatedFat != null ? widget.saturatedFat! * f : null;
      if (widget.isLiquid && widget.amountMl != null) {
        scaledAmountMl = widget.amountMl! * scale;
      }
    }

    return FoodEntry(
      id: const Uuid().v4(),
      userId: widget.userId,
      foodId: _nonEmptyFoodId(widget.foodId),
      entryDate: widget.date,
      mealType: _mealType,
      name: widget.name,
      amount: amount,
      unit: unitToStore,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      saturatedFat: saturatedFat,
      isLiquid: widget.isLiquid,
      amountMl: scaledAmountMl,
      isMeal: widget.isMeal,
      estimateLevel: _estimateLevel,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Compact "how sure?" override — a small row of chips, pre-set to the
  /// auto-derived level; tapping marks it user-overridden.
  Widget _buildEstimateRow(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.estimateLabel,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: EstimateLevel.values.map((lvl) {
            // ExcludeFocus: keep the chip from stealing focus so tapping it
            // doesn't dismiss the keyboard and drop the tap. See
            // add_food_entry_screen for the full explanation.
            return ExcludeFocus(
              child: ChoiceChip(
                label: Text(lvl.localizedName(l),
                    style: const TextStyle(fontSize: 12)),
                selected: _estimateLevel == lvl,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _estimateLevel = lvl;
                  _userSetEstimate = true;
                }),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amount + Unit
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amountCtrl,
                  decoration: InputDecoration(
                    labelText: l.amount,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*'))
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              // Unit dropdown
              if (_availableUnits().length > 1)
                DropdownButton<String>(
                  value: _selectedUnit,
                  items: _availableUnits()
                      .map((unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(unit, style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (newUnit) {
                    if (newUnit != null) _onUnitChanged(newUnit);
                  },
                )
              else
                Text(
                  _selectedUnit,
                  style: const TextStyle(fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Nutrition preview
          _NutritionPreview(entry: _buildEntry()),
          const SizedBox(height: 12),
          // How sure? — auto-derived from the portion type, overridable.
          _buildEstimateRow(l),
          const SizedBox(height: 12),
          // Meal type — compact dropdown rather than a row of chips. The chip
          // version wrapped to two lines on narrow phones and the second row
          // got clipped behind the dialog's action buttons, leaving some
          // meal types unselectable.
          Row(
            children: [
              Text('${l.mealType}:', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<MealType>(
                  value: _mealType,
                  isDense: true,
                  isExpanded: true,
                  items: MealType.values
                      .map((mt) => DropdownMenuItem(
                            value: mt,
                            child: Text(
                              '${mt.icon} ${mt.localizedName(l)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: (mt) {
                    if (mt == null) return;
                    setState(() => _mealType = mt);
                    widget.onMealTypeChanged(mt);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Save as shortcut
        TextButton.icon(
          icon: _savingShortcut
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.push_pin_outlined, size: 16),
          label: Text(l.shortcut),
          onPressed: _savingShortcut
              ? null
              : () async {
                  setState(() => _savingShortcut = true);
                  final entry = _buildEntry();
                  await widget.onSaveAsShortcut(
                    label: widget.name,
                    foodId: _nonEmptyFoodId(widget.foodId),
                    mealType: _mealType.toJson(),
                    amount: entry.amount,
                    unit: entry.unit,
                    calories: entry.calories,
                    protein: entry.protein,
                    fat: entry.fat,
                    carbs: entry.carbs,
                    fiber: entry.fiber,
                    sugar: entry.sugar,
                    sodium: entry.sodium,
                    saturatedFat: entry.saturatedFat,
                    isLiquid: entry.isLiquid,
                    amountMl: entry.amountMl,
                    isMeal: entry.isMeal,
                  );
                  setState(() => _savingShortcut = false);
                },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((entry: _buildEntry(), amountG: _currentAmountG())),
          child: Text(l.add),
        ),
      ],
    );
  }
}

// ── Nutrition preview ─────────────────────────────────────────────────────────

class _NutritionPreview extends StatelessWidget {
  final FoodEntry entry;

  const _NutritionPreview({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MacroChip(label: 'kcal',
              value: entry.calories.toStringAsFixed(0)),
          _MacroChip(label: l.macroProteinShort,
              value: '${entry.protein.toStringAsFixed(1)}g'),
          _MacroChip(label: l.macroFatShort,
              value: '${entry.fat.toStringAsFixed(1)}g'),
          _MacroChip(label: l.macroCarbsShort,
              value: '${entry.carbs.toStringAsFixed(1)}g'),
        ],
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final String value;

  const _MacroChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

