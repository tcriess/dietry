import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
import '../utils/unit_utils.dart';
import 'package:flutter/services.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../models/food_item.dart';
import '../models/food_search_result.dart';
import '../models/food_entry.dart';
import '../models/food_portion.dart';
import '../models/tag.dart';
import '../services/food_database_service.dart';
import '../services/tag_service.dart';
import '../services/neon_database_service.dart';
import '../services/food_image_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/user_food_prefs_service.dart';
import '../services/food_search_service.dart';
import '../services/local_data_service.dart';
import '../services/app_logger.dart';
import '../services/anonymous_auth_service.dart';
import '../app_config.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';
import '../widgets/food_thumbnail_widget.dart';
import '../widgets/tag_editor.dart';
import '../widgets/barcode_scanner_sheet.dart';
import '../widgets/cooked_factor_dialog.dart';
import '../widgets/cooked_weight_nudge.dart';
import '../services/barcode_lookup_service.dart';
import '../services/cooking_yield.dart';
import 'food_database_screen.dart';

/// Screen zum Hinzufügen eines Food-Entries
///
/// Workflow:
/// 1. Suche Food in Datenbank (optional)
/// 2. Wähle Menge & Einheit
/// 3. Wähle Meal Type
/// 4. Speichere Entry
enum _FoodSortOrder { alphabetical, newest, recentlyUsed }

class AddFoodEntryScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime? selectedDate;
  final MealType? initialMealType;
  final FoodItem? preselectedFood;

  /// When true, the nutrition-label OCR scan is launched automatically on
  /// open — used by the add sheet's 1-tap label-scan shortcut.
  final bool autoScanLabel;

  const AddFoodEntryScreen({
    super.key,
    this.dbService,
    this.selectedDate,
    this.initialMealType,
    this.preselectedFood,
    this.autoScanLabel = false,
  });

  @override
  State<AddFoodEntryScreen> createState() => _AddFoodEntryScreenState();
}

MealType _mealTypeForCurrentTime() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 10) return MealType.breakfast; // 05–10 Uhr
  if (hour >= 10 && hour < 14) return MealType.lunch; // 10–14 Uhr
  if (hour >= 14 && hour < 18) return MealType.snack; // 14–18 Uhr
  return MealType.dinner; // 18–05 Uhr
}

class _AddFoodEntryScreenState extends State<AddFoodEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fiberController = TextEditingController();
  final _sugarController = TextEditingController();
  final _sodiumController = TextEditingController();
  final _saturatedFatController = TextEditingController();

  // State
  FoodItem? _selectedFood;
  Map<String, double> _selectedMicros = const {};
  List<FoodSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showManualEntry = false;
  MealType _selectedMealType = _mealTypeForCurrentTime();
  FoodPortion? _selectedPortion; // null = custom g/ml Eingabe
  String _customUnit = 'g'; // 'g' oder 'ml' wenn _selectedPortion == null
  // How sure the user is of amount/values — drives the nutrition uncertainty
  // band. The default auto-derives from portion type + the food's own level;
  // once the user taps a chip we honour their choice.
  EstimateLevel _estimateLevel = EstimateLevel.none;
  bool _userSetEstimate = false;
  EstimateLevel _autoEstimate() {
    final level = EstimateLevel.defaultForLog(
      foodLevel: _selectedFood?.estimateLevel ?? EstimateLevel.none,
    );
    // Converting a cooked weight with a *generic* yield factor adds spread on
    // top of whatever the food itself carries. A factor the user measured
    // themselves does not — that is as good as weighing.
    final yield_ = _cookedYield;
    if (yield_ != null && _isCookedUnitSelected && _userCookedFactor == null) {
      return level.orHigher(yield_.uncertainty);
    }
    return level;
  }

  EstimateLevel get _effectiveEstimate =>
      _userSetEstimate ? _estimateLevel : _autoEstimate();

  // Raw→cooked yield for the selected food, memoized per food instance — the
  // lookup runs regexes and is read several times per build.
  FoodItem? _yieldCacheFood;
  CookingYieldInfo? _yieldCacheInfo;
  CookingYieldInfo? get _cookedYield {
    final food = _selectedFood;
    if (food == null) return null;
    if (!identical(_yieldCacheFood, food)) {
      _yieldCacheFood = food;
      _yieldCacheInfo = CookingYield.defaultFor(food);
    }
    return _yieldCacheInfo;
  }

  /// The user's own measured factor for the selected food, if they have one.
  /// Beats the generic table — most of the published spread in cooking yields
  /// is how a given person cooks, not measurement error.
  double? _userCookedFactor;

  double? get _effectiveCookedFactor =>
      _userCookedFactor ?? _cookedYield?.factor;

  /// The custom unit, falling back to plain grams when a stale `g_cooked`
  /// selection survives a food change that leaves us without a yield factor.
  String get _effectiveCustomUnit =>
      (_customUnit == kUnitGramCooked && _cookedYield == null)
          ? kUnitGram
          : _customUnit;

  bool get _isCookedUnitSelected =>
      _selectedPortion == null && _effectiveCustomUnit == kUnitGramCooked;

  /// Set once the user picks any unit — the raw/cooked nudge is a question, and
  /// touching the dropdown answers it either way.
  bool _unitTouched = false;

  /// Whether to point out that the values are for the raw/dry product. Limited
  /// to water-absorbing dry goods, where the factor is 2–3× and the conversion
  /// is exact; the ±25% meat case is not worth interrupting for.
  bool get _showCookedNudge =>
      !_unitTouched &&
      !_isCookedUnitSelected &&
      _cookedYield?.kind == YieldKind.absorption;

  /// Loads the user's measured factor for [food], if any. Fire-and-forget: on
  /// failure (offline — user_food_prefs is not in the local mirror) the generic
  /// factor stands, which is the same behaviour as never having measured.
  Future<void> _loadCookedFactor(FoodItem food) async {
    final db = widget.dbService;
    if (db == null || food.id.isEmpty) return;
    if (CookingYield.defaultFor(food) == null) return; // nothing to override
    final prefs = await UserFoodPrefsService(db).getForFoodIds([food.id]);
    final factor = prefs[food.id]?.cookedFactor;
    // The user may have moved on to another food while this was in flight.
    if (!mounted || factor == null || !identical(_selectedFood, food)) return;
    setState(() => _userCookedFactor = factor);
  }

  Future<void> _openCookedCalibration() async {
    final food = _selectedFood;
    final generic = _cookedYield;
    if (food == null || generic == null) return;

    final result = await showCookedFactorDialog(
      context,
      defaultFactor: generic.factor,
      currentFactor: _userCookedFactor,
    );
    if (result == null || !mounted) return;

    setState(() => _userCookedFactor = result.factor);

    // Guest mode / unsaved food: the factor still applies to this entry, it
    // just can't be remembered.
    final db = widget.dbService;
    if (db == null || food.id.isEmpty) return;

    final ok = await UserFoodPrefsService(db).upsertCookedFactor(
      foodId: food.id,
      factor: result.factor,
      amount: tryParseDouble(_amountController.text) ?? 100,
      unit: _effectiveCustomUnit,
    );
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l.cookedCalibrateSaved : l.cookedCalibrateFailed),
    ));
  }

  void _switchToCookedUnit() {
    final yield_ = _cookedYield;
    if (yield_ == null) return;
    // Grams the current selection represents on the raw/dry basis — resolves a
    // named portion too, so the switch works from whatever unit was selected.
    final rawGrams = _currentGrams();
    setState(() {
      _unitTouched = true;
      _selectedPortion = null;
      _customUnit = kUnitGramCooked;
      if (rawGrams > 0) {
        // Show what that raw weight becomes cooked, so the switch doesn't
        // silently change how much food was logged.
        _amountController.text =
            (rawGrams * _effectiveCookedFactor!).round().toString();
      }
    });
  }
  bool _isSaving = false;
  bool _useOpenFoodFacts = false;
  bool _isLiquid = false;

  // Debounce timer for the search field (avoids hitting the DB on every keystroke).
  Timer? _searchDebounce;

  // Guest mode: optional anonymous JWT for public food DB access
  NeonDatabaseService? _anonDbService;
  late FoodImageService _imageService;
  final Map<String, String?> _imageCache = {};

  // Tag filtering
  late TagService _tagService;
  List<Tag> _availableTags = [];
  final Set<String> _selectedTagSlugs = {}; // tag slugs selected for filtering
  bool _tagsLoading = true;

  // Own foods preloaded list (authenticated mode)
  List<FoodItem> _myFoods = [];
  bool _isLoadingMyFoods = false;
  List<String> _recentlyUsedFoodIds = [];
  _FoodSortOrder _sortOrder = _FoodSortOrder.recentlyUsed;

  List<FoodItem> get _displayedMyFoods {
    var foods = List<FoodItem>.from(_myFoods);

    if (_selectedTagSlugs.isNotEmpty) {
      foods = foods.where((f) {
        final slugs = f.tags.map((t) => t.slug).toSet();
        return _selectedTagSlugs.every(slugs.contains);
      }).toList();
    }

    final q = _searchController.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      foods = foods
          .where((f) =>
              f.name.toLowerCase().contains(q) ||
              (f.brand?.toLowerCase().contains(q) ?? false) ||
              (f.category?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    switch (_sortOrder) {
      case _FoodSortOrder.alphabetical:
        foods.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _FoodSortOrder.newest:
        foods.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _FoodSortOrder.recentlyUsed:
        final order = {
          for (var i = 0; i < _recentlyUsedFoodIds.length; i++)
            _recentlyUsedFoodIds[i]: i
        };
        foods.sort((a, b) {
          final ai = order[a.id] ?? _recentlyUsedFoodIds.length;
          final bi = order[b.id] ?? _recentlyUsedFoodIds.length;
          if (ai != bi) return ai.compareTo(bi);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }

    return foods;
  }

  Future<void> _loadMyFoods() async {
    if (widget.dbService == null) return;
    setState(() => _isLoadingMyFoods = true);
    try {
      final foods =
          await FoodDatabaseService(widget.dbService!).getVisibleFoods();
      if (mounted) setState(() => _myFoods = foods);
    } catch (e) {
      appLogger.w('⚠️ Foods konnten nicht geladen werden: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMyFoods = false);
    }
  }

  Future<void> _loadRecentlyUsedFoodIds() async {
    if (widget.dbService == null) return;
    try {
      final ids =
          await FoodDatabaseService(widget.dbService!).getRecentlyUsedFoodIds();
      if (mounted) setState(() => _recentlyUsedFoodIds = ids);
    } catch (e) {
      appLogger.w('⚠️ MRU Foods konnten nicht geladen werden: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Only initialize DB-dependent services if dbService is available (not guest mode)
    if (widget.dbService != null) {
      _imageService = FoodImageService(widget.dbService!);
      _tagService = TagService(widget.dbService!);
      _loadAvailableTags();
      _loadMyFoods();
      _loadRecentlyUsedFoodIds();
    } else {
      // Guest mode: try to get anonymous token for public food DB access
      _tagsLoading = false;
      _initializeAnonDbService();
    }
    if (widget.initialMealType != null) {
      _selectedMealType = widget.initialMealType!;
    }
    // Pre-select food if provided from FoodDetailScreen
    if (widget.preselectedFood != null) {
      _selectFood(widget.preselectedFood!);
    }
    // Launched via the add sheet's label-scan shortcut → go straight to OCR.
    if (widget.autoScanLabel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanNutritionLabel();
      });
    }
  }

  /// Initialize anonymous DB service for guest mode (read-only public foods).
  Future<void> _initializeAnonDbService() async {
    try {
      final token = await AnonymousAuthService.getToken(AppConfig.authBaseUrl);
      if (token != null) {
        // Create new service instance for anonymous access
        final anonDb = NeonDatabaseService();
        // Initialize Dio HTTP client
        await anonDb.init();
        // Set the anonymous JWT token
        try {
          await anonDb.setJWT(token);
        } catch (e) {
          // setJWT() might fail if token is expired or invalid
          // but it will retry/refresh, so let's just log and continue
          appLogger.w('⚠️ setJWT() warning: $e');
        }
        if (mounted) {
          setState(() {
            _anonDbService = anonDb;
          });
          appLogger.i('✅ Guest mode: anonymous DB service initialized');
        }
      } else {
        appLogger.d('ℹ️ Guest mode: anonymous token endpoint not available');
        // Continue without anonymous access — external APIs (USDA, OFF) still work
      }
    } catch (e) {
      appLogger
          .w('⚠️ Guest mode: failed to initialize anonymous DB access: $e');
      // Continue without anonymous access — external APIs (USDA, OFF) still work
    }
  }

  Future<void> _loadAvailableTags() async {
    try {
      final tags = await _tagService.getAvailableFoodTags();
      if (mounted) {
        setState(() {
          _availableTags = tags;
          _tagsLoading = false;
        });
      }
    } catch (e) {
      appLogger.e('Error loading available tags: $e');
      setState(() => _tagsLoading = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _saturatedFatController.dispose();
    super.dispose();
  }

  /// Suche Foods: entweder in Datenbank ("own db") ODER externe APIs
  Future<void> _searchFoods(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final List<FoodSearchResult> results = [];

      if (_useOpenFoodFacts) {
        // User selected external APIs (USDA + Open Food Facts)
        final externalResults = await FoodSearchService().search(query);
        results.addAll(externalResults);
      } else {
        // User selected "own db" - search database only (no API calls)
        if (widget.dbService != null) {
          // Authenticated mode: search own + public foods in database
          final items =
              await FoodDatabaseService(widget.dbService!).searchFoods(
            query,
            limit: 20,
            filterTags: _selectedTagSlugs.toList(),
          );
          results.addAll(items.map((f) => FoodSearchResult(food: f)));
        } else {
          // Guest mode: search public foods database + local guest foods (no external APIs)
          // Search public foods database if anonymous JWT available
          if (_anonDbService != null) {
            try {
              final items =
                  await FoodDatabaseService(_anonDbService!).searchFoods(
                query,
                limit: 20,
              );
              results.addAll(items.map((f) => FoodSearchResult(food: f)));
              appLogger
                  .d('🔍 Found ${items.length} public foods from anonymous DB');
            } catch (e) {
              appLogger.w('⚠️ Anonymous food search failed: $e');
            }
          }

          // Search locally stored guest foods
          try {
            final guestFoods =
                await LocalDataService.instance.searchGuestFoods(query);
            results.addAll(guestFoods.map((f) => FoodSearchResult(food: f)));
            appLogger.d(
                '🔍 Found ${guestFoods.length} guest foods from local storage');
          } catch (e) {
            appLogger.w('⚠️ Guest food search failed: $e');
          }
        }
      }

      // Remove duplicates by food ID
      final uniqueResults = <String, FoodSearchResult>{};
      for (final result in results) {
        final key = result.food.id;
        uniqueResults[key] = result;
      }

      setState(() {
        _searchResults = uniqueResults.values.toList();
        _isSearching = false;
      });
    } catch (e) {
      appLogger.e('❌ Fehler bei Food-Suche: $e');
      setState(() {
        _isSearching = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei Suche: $e')),
        );
      }
    }
  }

  /// Wähle Food aus Suchergebnissen.
  ///
  /// Befüllt die Nährwert-Controller immer mit den per-100g-Werten des Foods
  /// (nicht skaliert). Ein separater Totals-Preview zeigt den skalierten Wert.
  ///
  /// [preservedAmountG]: falls gesetzt (z.B. nach Rückkehr vom "Zur Datenbank
  /// hinzufügen"-Dialog), wird der ursprüngliche Mengen-Input des Users erhalten.
  /// Passt eine Portion exakt zu dieser Grammzahl, wird sie ausgewählt; sonst
  /// wird die Menge in g/ml beibehalten.
  void _selectFood(
    FoodItem food, {
    Map<String, double> micros = const {},
    double? preservedAmountG,
  }) {
    setState(() {
      _selectedFood = food;
      _selectedMicros = micros;
      _nameController.text = food.name;
      // New food, new question — the unit choice made for the previous one says
      // nothing about this one.
      _unitTouched = false;
      _userCookedFactor = null;

      // Per-100g-Werte aus FoodItem in die Controller schreiben — NICHT skalieren.
      _caloriesController.text = food.calories.toStringAsFixed(0);
      _proteinController.text = food.protein.toStringAsFixed(1);
      _fatController.text = food.fat.toStringAsFixed(1);
      _carbsController.text = food.carbs.toStringAsFixed(1);
      _fiberController.text =
          food.fiber != null ? food.fiber!.toStringAsFixed(1) : '';
      _sugarController.text =
          food.sugar != null ? food.sugar!.toStringAsFixed(1) : '';
      _sodiumController.text =
          food.sodium != null ? food.sodium!.toStringAsFixed(1) : '';
      _saturatedFatController.text = food.saturatedFat != null
          ? food.saturatedFat!.toStringAsFixed(1)
          : '';

      _isLiquid = food.isLiquid;

      if (preservedAmountG != null && preservedAmountG > 0) {
        // Nach "zur DB hinzufügen": User-Menge erhalten.
        final matching = food.portions
            .where((p) => p.amountG == preservedAmountG)
            .firstOrNull;
        if (matching != null) {
          _selectedPortion = matching;
          _amountController.text = '1';
        } else {
          _selectedPortion = null;
          _customUnit = food.isLiquid ? 'ml' : 'g';
          _amountController.text =
              preservedAmountG == preservedAmountG.truncateToDouble()
                  ? preservedAmountG.toInt().toString()
                  : preservedAmountG.toStringAsFixed(1);
        }
      } else {
        // Standard: erste Portion auswählen, sonst servingSize oder 100g.
        if (food.portions.isNotEmpty) {
          _selectedPortion = food.portions.first;
          _amountController.text = '1';
        } else {
          _selectedPortion = null;
          final unit = food.servingUnit ?? 'g';
          _customUnit = (unit.startsWith('ml') || food.isLiquid) ? 'ml' : 'g';
          _amountController.text = food.servingSize != null
              ? food.servingSize!.toInt().toString()
              : '100';
        }
      }

      // Verberge Suchergebnisse
      _searchResults = [];
      _showManualEntry = false;
    });

    unawaited(_loadCookedFactor(food));
  }

  /// Öffnet den OCR-Scan-Flow (Premium, mobile) und prefillt die
  /// manuelle Eingabemaske mit den erkannten Werten.
  Future<void> _scanNutritionLabel() async {
    if (!AppFeatures.nutritionLabelScan) return;
    final locale = Localizations.localeOf(context);
    final result = await premiumFeatures.scanNutritionLabel(
      context: context,
      preferredLocale: locale,
    );
    if (!mounted || result == null) return;

    String fmt(double? v, {int digits = 1}) =>
        v == null ? '' : v.toStringAsFixed(digits);

    setState(() {
      _showManualEntry = true;
      _selectedFood = null;
      _searchResults = [];
      _amountController.text = '100';
      _customUnit = 'g';
      if (result.productName != null) {
        _nameController.text = result.productName!;
      }
      _caloriesController.text = fmt(result.caloriesPer100g, digits: 0);
      _proteinController.text = fmt(result.proteinPer100g);
      _fatController.text = fmt(result.fatPer100g);
      _carbsController.text = fmt(result.carbsPer100g);
      _saturatedFatController.text = fmt(result.satFatPer100g);
      _sugarController.text = fmt(result.sugarPer100g);
      _fiberController.text = fmt(result.fiberPer100g);
      _sodiumController.text = fmt(result.saltPer100g, digits: 2);
    });

    if (result.warnings.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warnings.join(' ')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Opens the barcode scanner, looks up the scanned barcode in the local DB
  /// and Open Food Facts, and selects the food if found. On an OFF hit, also
  /// silently persists the food into the user's own DB (with the scanned
  /// barcode, no portions) so the next scan resolves locally — portions get
  /// added later via the food database screen when the user knows them.
  Future<void> _scanBarcode() async {
    final barcode = await showBarcodeScannerSheet(context);
    if (barcode == null || !mounted) return;

    setState(() => _isSearching = true);

    final locale = Localizations.localeOf(context).languageCode;
    final dbService = widget.dbService != null
        ? FoodDatabaseService(widget.dbService!)
        : null;
    final result = await BarcodeLookupService.lookup(
      barcode,
      dbService: dbService,
      locale: locale,
    );

    if (!mounted) return;

    final l = AppLocalizations.of(context);
    if (result == null) {
      setState(() => _isSearching = false);
      final db = widget.dbService;
      if (db != null) {
        // Offer to create a new food carrying the scanned barcode, then select
        // it so the user can log an entry for it.
        final created = await createFoodFromScannedBarcode(
          context: context,
          dbService: db,
          barcode: barcode,
        );
        if (created != null && mounted) {
          _selectFood(created);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l?.barcodeNotFound ?? 'Produkt nicht gefunden')),
        );
      }
      return;
    }

    // OFF hit + we have a user DB → silently save before selecting so the
    // entry foodId points at the persistent row, not the one-shot OFF copy.
    FoodItem foodForSelect = result.food;
    Map<String, double> microsForSelect = result.micros;
    if (result.fromOff && widget.dbService != null) {
      try {
        final created = await FoodDatabaseService(widget.dbService!)
            .createFood(result.food.copyWith(barcode: barcode));
        if (result.micros.isNotEmpty) {
          final userId = widget.dbService!.userId;
          final jwt = widget.dbService!.jwt;
          if (userId != null && jwt != null) {
            await premiumFeatures.saveFoodDatabaseMicrosFromMap(
              foodId: created.id,
              userId: userId,
              micros100g: result.micros,
              authToken: jwt,
              apiUrl: NeonDatabaseService.dataApiUrl,
            );
          }
        }
        foodForSelect = created;
      } catch (e) {
        appLogger.w('⚠️ Silent OFF→own save failed: $e');
        // Fall through; the entry logs from the OFF row as before.
      }
    }

    if (!mounted) return;
    setState(() => _isSearching = false);
    _selectFood(foodForSelect, micros: microsForSelect);

    if (result.fromOff) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${l?.barcodeFoundOff ?? 'Open Food Facts'}: ${result.food.name}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Grams equivalent of the current amount+unit, on the food's label basis
  /// (used for scaling per-100g values). For portions: amount × portion.amountG.
  /// For custom g/ml units: amount directly. For a cooked weight: converted back
  /// to the raw/dry weight the label declares.
  double _currentGrams() {
    final rawAmount = tryParseDouble(_amountController.text) ?? 0;
    if (rawAmount <= 0) return 0;
    return unitToGrams(
          rawAmount,
          _effectiveCustomUnit,
          portion: _selectedPortion,
          cookedFactor: _effectiveCookedFactor,
        ) ??
        0;
  }

  /// Compute total nutrition for the current amount from per-100g values in the
  /// controllers. Pure calculation — does NOT mutate controllers, which always
  /// hold per-100g values.
  Map<String, double> _computeTotals() {
    final grams = _currentGrams();
    if (grams <= 0) {
      return const {'calories': 0, 'protein': 0, 'fat': 0, 'carbs': 0};
    }
    final factor = grams / 100.0;
    return {
      'calories': (tryParseDouble(_caloriesController.text) ?? 0) * factor,
      'protein': (tryParseDouble(_proteinController.text) ?? 0) * factor,
      'fat': (tryParseDouble(_fatController.text) ?? 0) * factor,
      'carbs': (tryParseDouble(_carbsController.text) ?? 0) * factor,
    };
  }

  /// Card showing total nutrition for the current amount.
  /// Confidence picker: how sure is the user of amount/values? Feeds
  /// [FoodEntry.estimateLevel] → the daily uncertainty band.
  Widget _buildEstimatePicker() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.estimateLabel,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: EstimateLevel.values.map((lvl) {
            // ExcludeFocus: a bare ChoiceChip requests focus when tapped, which
            // unfocuses the amount/nutrition field, dismisses the keyboard and
            // resizes the sheet mid-gesture — so the chip slides out from under
            // the finger and the tap is dropped (the chips look "unselectable"
            // whenever the keyboard is up). Not taking focus keeps the keyboard
            // open and the layout stable, so the tap lands.
            return ExcludeFocus(
              child: ChoiceChip(
                label: Text(lvl.localizedName(l)),
                selected: _effectiveEstimate == lvl,
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

  Widget _buildTotalsPreview() {
    final l = AppLocalizations.of(context)!;
    final totals = _computeTotals();
    final rawAmount = tryParseDouble(_amountController.text) ?? 0;
    if (rawAmount <= 0) return const SizedBox.shrink();

    final amountStr = rawAmount == rawAmount.truncateToDouble()
        ? rawAmount.toInt().toString()
        : rawAmount.toStringAsFixed(1);
    final unitText = _selectedPortion?.name ??
        unitLabel(_effectiveCustomUnit, l,
            distinguishRaw: _cookedYield != null);

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.totalForAmount('$amountStr$unitText'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            // Make the raw↔cooked conversion visible: the user should see which
            // weight the nutrition values are actually being scaled from.
            if (_isCookedUnitSelected)
              Text(
                _userCookedFactor != null
                    ? '${l.cookedHintRaw(formatAmount(_currentGrams()))} · ${l.cookedFactorOwn}'
                    : l.cookedHintRaw(formatAmount(_currentGrams())),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _PreviewMacro('kcal', totals['calories']!.toStringAsFixed(0)),
                _PreviewMacro(l.macroProteinShort,
                    '${totals['protein']!.toStringAsFixed(1)}g'),
                _PreviewMacro(
                    l.macroFatShort, '${totals['fat']!.toStringAsFixed(1)}g'),
                _PreviewMacro(l.macroCarbsShort,
                    '${totals['carbs']!.toStringAsFixed(1)}g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dropdown zur Portionsauswahl (benannte Portionen + g/ml)
  Widget _buildPortionSelector() {
    final l = AppLocalizations.of(context)!;
    final food = _selectedFood;
    var portions = food?.portions ?? [];

    // Deduplicate portions by name (keep first occurrence)
    final seenNames = <String>{};
    portions = portions.where((p) {
      if (seenNames.contains(p.name)) {
        return false;
      }
      seenNames.add(p.name);
      return true;
    }).toList();

    // Berechne den aktuellen Schlüssel
    final currentKey = _selectedPortion != null
        ? 'p:${_selectedPortion!.name}'
        : _effectiveCustomUnit;

    // Packaged/label values are declared for the food as sold — raw or dry.
    // Offer a cooked weight only where cooking actually moves the number.
    final yield_ = _cookedYield;

    final items = <DropdownMenuItem<String>>[];

    // Benannte Portionen
    for (final p in portions) {
      items.add(DropdownMenuItem(
        value: 'p:${p.name}',
        child: Text(
            '${p.name} (${p.amountG % 1 == 0 ? p.amountG.toInt() : p.amountG}g)'),
      ));
    }

    // Immer: g und ml
    items.add(DropdownMenuItem(
      value: kUnitGram,
      child: Text(unitLabel(kUnitGram, l, distinguishRaw: yield_ != null)),
    ));
    if (yield_ != null) {
      items.add(DropdownMenuItem(
        value: kUnitGramCooked,
        child: Text(unitLabel(kUnitGramCooked, l)),
      ));
    }
    items.add(DropdownMenuItem(value: kUnitMl, child: Text(unitLabel(kUnitMl, l))));

    return DropdownButtonFormField<String>(
      initialValue: currentKey,
      decoration: InputDecoration(
        labelText: l.unit,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _unitTouched = true;
          if (value.startsWith('p:')) {
            final name = value.substring(2);
            _selectedPortion = food?.portions.firstWhere((p) => p.name == name);
            _amountController.text = '1';
          } else {
            _selectedPortion = null;
            _customUnit = value;
            final serving = food?.servingSize;
            if (serving != null && value == kUnitGram) {
              _amountController.text = serving.toInt().toString();
            } else if (serving != null && value == kUnitGramCooked) {
              // The serving size is a raw weight — show what it becomes cooked.
              _amountController.text =
                  (serving * _effectiveCookedFactor!).round().toString();
            }
          }
          // setState rebuilds the totals preview; nutrition controllers stay per-100g.
        });
      },
    );
  }

  /// Speichere Food Entry
  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final dbService = widget.dbService;
      final userId = dbService?.userId ?? ''; // Guest mode: empty userId

      final rawAmount = parseDouble(_amountController.text);

      // Calculate amountMl for liquid foods
      double? amountMl;
      if (_isLiquid) {
        if (_selectedPortion != null) {
          // Portion: amount * portion.amountG (treating G as ml for liquid foods)
          amountMl = rawAmount * _selectedPortion!.amountG;
        } else if (_effectiveCustomUnit == kUnitMl) {
          // Direct ml entry
          amountMl = rawAmount;
        }
      }

      // Nutrition controllers are ALWAYS per-100g (both manual entry and selected
      // food). Scale to totals by actual grams — same resolution the live preview
      // uses, so the saved entry can never disagree with what the user saw.
      final grams = _currentGrams();
      final scale = grams / 100.0;

      final entry = FoodEntry(
        id: '', // Wird von DB generiert
        userId: userId,
        foodId:
            (_selectedFood?.id.isNotEmpty == true) ? _selectedFood!.id : null,
        entryDate: widget.selectedDate ?? DateTime.now(),
        mealType: _selectedMealType,
        name: _nameController.text,
        amount: rawAmount,
        unit: _selectedPortion?.name ?? _effectiveCustomUnit,
        calories: parseDouble(_caloriesController.text) * scale,
        protein: parseDouble(_proteinController.text) * scale,
        fat: parseDouble(_fatController.text) * scale,
        carbs: parseDouble(_carbsController.text) * scale,
        fiber: tryParseDouble(_fiberController.text) != null
            ? parseDouble(_fiberController.text) * scale
            : null,
        sugar: tryParseDouble(_sugarController.text) != null
            ? parseDouble(_sugarController.text) * scale
            : null,
        sodium: tryParseDouble(_sodiumController.text) != null
            ? parseDouble(_sodiumController.text) * scale
            : null,
        saturatedFat: tryParseDouble(_saturatedFatController.text) != null
            ? parseDouble(_saturatedFatController.text) * scale
            : null,
        isLiquid: _isLiquid,
        amountMl: amountMl,
        isMeal: false,
        estimateLevel: _effectiveEstimate,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await SyncService.instance.createFoodEntry(entry);
      // Add the server entity (real id) or the optimistic entry (queued offline).
      final effective = saved ?? entry;
      DataStore.instance.addFoodEntry(effective);

      // Remember the portion (amount + unit) for this food so the quick-add
      // sheet pre-fills it next time. Fire-and-forget; auth-only.
      if (dbService != null) {
        final prefFoodId = entry.foodId;
        if (prefFoodId != null && prefFoodId.isNotEmpty) {
          unawaited(UserFoodPrefsService(dbService).upsert(
            foodId: prefFoodId,
            amount: entry.amount,
            unit: entry.unit,
          ));
        }
      }

      // Auto-copy micro nutrients (best-effort, fire-and-forget).
      // Only in authenticated mode (cloud feature).
      if (dbService != null) {
        final amountG = _selectedPortion != null
            ? rawAmount * _selectedPortion!.amountG
            : rawAmount;
        final foodId = entry.foodId;
        final jwt = dbService.jwt;
        if (saved != null && jwt != null) {
          if (foodId != null && foodId.isNotEmpty) {
            // Food aus eigener DB: Mikros aus food_database_micros kopieren
            premiumFeatures.copyFoodMicrosToEntry(
              foodId: foodId,
              entryId: saved.id,
              userId: userId,
              amountG: amountG,
              authToken: jwt,
              apiUrl: NeonDatabaseService.dataApiUrl,
            );
          } else if (_selectedMicros.isNotEmpty) {
            // Food aus OFF/USDA: Mikros direkt aus API-Daten schreiben
            premiumFeatures.saveFoodEntryMicrosFromMap(
              entryId: saved.id,
              userId: userId,
              micros100g: _selectedMicros,
              amountG: amountG,
              authToken: jwt,
              apiUrl: NeonDatabaseService.dataApiUrl,
            );
          }
        }
      }

      if (mounted) {
        final lCtx = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lCtx.entrySaved),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Speichere aktuelles Food zur Datenbank (remote) oder lokal (guest mode)
  Future<void> _saveFoodToDatabase() async {
    // In guest mode: save locally instead of to remote database
    if (widget.dbService == null) {
      await _saveFoodLocally();
      return;
    }

    // Für externe Ergebnisse (OFF, USDA): Nährwerte direkt aus _selectedFood (per 100g),
    // nicht aus den skalierten Controllern.
    final isExternal = _selectedFood != null && _selectedFood!.id.isEmpty;
    final initialCalories = isExternal
        ? _selectedFood!.calories
        : (tryParseDouble(_caloriesController.text) ?? 0);
    final initialProtein = isExternal
        ? _selectedFood!.protein
        : (tryParseDouble(_proteinController.text) ?? 0);
    final initialFat = isExternal
        ? _selectedFood!.fat
        : (tryParseDouble(_fatController.text) ?? 0);
    final initialCarbs = isExternal
        ? _selectedFood!.carbs
        : (tryParseDouble(_carbsController.text) ?? 0);
    final initialFiber = isExternal
        ? _selectedFood!.fiber
        : tryParseDouble(_fiberController.text);
    final initialSugar = isExternal
        ? _selectedFood!.sugar
        : tryParseDouble(_sugarController.text);
    final initialSodium = isExternal
        ? _selectedFood!.sodium
        : tryParseDouble(_sodiumController.text);
    final initialSaturatedFat = isExternal
        ? _selectedFood!.saturatedFat
        : tryParseDouble(_saturatedFatController.text);

    if (!isExternal && !_formKey.currentState!.validate()) return;

    // Zeige Dialog mit erweiterten Optionen
    final result = await showDialog<AddFoodDialogResult>(
      context: context,
      builder: (context) => _AddFoodToDatabaseDialog(
        initialName: _nameController.text,
        initialCalories: initialCalories,
        initialProtein: initialProtein,
        initialFat: initialFat,
        initialCarbs: initialCarbs,
        initialFiber: initialFiber,
        initialSugar: initialSugar,
        initialSodium: initialSodium,
        initialSaturatedFat: initialSaturatedFat,
        initialCategory: _selectedFood?.category,
        initialBrand: _selectedFood?.brand,
        initialPortions: _selectedFood?.portions ?? [],
        initialMicros: _selectedMicros,
        initialIsLiquid: _selectedFood?.isLiquid ?? _isLiquid,
        dbService: widget.dbService!,
      ),
    );

    if (result != null) {
      try {
        final service = FoodDatabaseService(widget.dbService!);
        final created = await service.createFood(result.food);

        // Save tags if any were added
        if (result.food.tags.isNotEmpty) {
          appLogger.d(
              '💾 Saving ${result.food.tags.length} tags for newly created food');
          final tagService = TagService(widget.dbService!);
          await tagService.setFoodTags(created.id, result.food.tags);
        }

        // Persist micronutrients (cloud) so the subsequent food entry can copy them.
        if (result.micros.isNotEmpty) {
          final userId = widget.dbService!.userId;
          final jwt = widget.dbService!.jwt;
          if (userId != null && jwt != null) {
            await premiumFeatures.saveFoodDatabaseMicrosFromMap(
              foodId: created.id,
              userId: userId,
              micros100g: result.micros,
              authToken: jwt,
              apiUrl: NeonDatabaseService.dataApiUrl,
            );
          }
        }

        if (mounted) {
          final prevGrams = _currentGrams();
          _selectFood(
            created,
            micros: result.micros,
            preservedAmountG: prevGrams > 0 ? prevGrams : null,
          );
          await _saveEntry();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Fehler: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Save food locally in guest mode
  Future<void> _saveFoodLocally() async {
    final isExternal = _selectedFood != null && _selectedFood!.id.isEmpty;
    final initialCalories = isExternal
        ? _selectedFood!.calories
        : (tryParseDouble(_caloriesController.text) ?? 0);
    final initialProtein = isExternal
        ? _selectedFood!.protein
        : (tryParseDouble(_proteinController.text) ?? 0);
    final initialFat = isExternal
        ? _selectedFood!.fat
        : (tryParseDouble(_fatController.text) ?? 0);
    final initialCarbs = isExternal
        ? _selectedFood!.carbs
        : (tryParseDouble(_carbsController.text) ?? 0);
    final initialFiber = isExternal
        ? _selectedFood!.fiber
        : tryParseDouble(_fiberController.text);
    final initialSugar = isExternal
        ? _selectedFood!.sugar
        : tryParseDouble(_sugarController.text);
    final initialSodium = isExternal
        ? _selectedFood!.sodium
        : tryParseDouble(_sodiumController.text);
    final initialSaturatedFat = isExternal
        ? _selectedFood!.saturatedFat
        : tryParseDouble(_saturatedFatController.text);

    if (!isExternal && !_formKey.currentState!.validate()) return;

    // Show dialog to create food
    final result = await showDialog<AddFoodDialogResult>(
      context: context,
      builder: (context) => _AddFoodToDatabaseDialog(
        initialName: _nameController.text,
        initialCalories: initialCalories,
        initialProtein: initialProtein,
        initialFat: initialFat,
        initialCarbs: initialCarbs,
        initialFiber: initialFiber,
        initialSugar: initialSugar,
        initialSodium: initialSodium,
        initialSaturatedFat: initialSaturatedFat,
        initialCategory: _selectedFood?.category,
        initialBrand: _selectedFood?.brand,
        initialPortions: _selectedFood?.portions ?? [],
        initialIsLiquid: _selectedFood?.isLiquid ?? _isLiquid,
        dbService: null, // No DB service in guest mode
      ),
    );

    if (result != null) {
      try {
        // Save locally
        final saved = await LocalDataService.instance.saveGuestFood(result.food);
        final prevGrams = _currentGrams();
        _selectFood(
          saved,
          preservedAmountG: prevGrams > 0 ? prevGrams : null,
        );

        if (mounted) {
          await _saveEntry();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Fehler: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Bearbeite ein eigenes Food direkt aus den Suchergebnissen
  Future<void> _editFoodInSearch(FoodItem food) async {
    // In guest mode: edit food is not available
    if (widget.dbService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Bearbeitung ist im Gast-Modus nicht verfügbar'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) =>
          FoodEditDialog(food: food, dbService: widget.dbService!),
    );
    if (result == null) return;

    try {
      final service = FoodDatabaseService(widget.dbService!);
      final updated = await service.updateFood(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${updated.name}" aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMyFoods();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Lösche ein eigenes Food direkt aus den Suchergebnissen
  Future<void> _deleteFoodInSearch(FoodItem food) async {
    // In guest mode: delete food is not available
    if (widget.dbService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Löschung ist im Gast-Modus nicht verfügbar'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lebensmittel löschen?'),
        content: Text(
          '"${food.name}" wird aus deiner Datenbank gelöscht.\n\n'
          'Bestehende Einträge werden nicht gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final service = FoodDatabaseService(widget.dbService!);
      await service.deleteFood(food.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
        // Falls das gelöschte Food gerade ausgewählt war, Auswahl aufheben
        if (_selectedFood?.id == food.id) {
          setState(() {
            _selectedFood = null;
            _nameController.clear();
            _amountController.clear();
            _caloriesController.clear();
            _proteinController.clear();
            _fatController.clear();
            _carbsController.clear();
          });
        }
        _loadMyFoods();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Öffne einen Tag-Editor für inline Tag-Verwaltung bei Search-Ergebnissen
  Future<void> _editFoodTagsInline(FoodItem food) async {
    final tags = await _tagService.getFoodTags(food.id);
    if (!mounted) return;

    final l = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${l?.tags ?? "Tags"} für "${food.name}"'),
        content: TagEditor(
          tags: tags,
          onChanged: (updatedTags) async {
            await _tagService.setFoodTags(food.id, updatedTags);
            appLogger.i('✅ Tags aktualisiert für: ${food.name}');
          },
          tagService: _tagService,
          readOnly: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
    if (mounted) _loadMyFoods();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.addFoodScreenTitle),
        actions: [
          // Sort order (only in My DB authenticated mode)
          if (widget.dbService != null &&
              !_showManualEntry &&
              !_useOpenFoodFacts)
            PopupMenuButton<_FoodSortOrder>(
              icon: const Icon(Icons.sort),
              tooltip: AppLocalizations.of(context)?.sortBy ?? 'Sortieren',
              initialValue: _sortOrder,
              onSelected: (order) => setState(() => _sortOrder = order),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _FoodSortOrder.recentlyUsed,
                  child: Row(children: [
                    Icon(
                        _sortOrder == _FoodSortOrder.recentlyUsed
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context)?.sortRecentlyUsed ??
                        'Zuletzt verwendet'),
                  ]),
                ),
                PopupMenuItem(
                  value: _FoodSortOrder.alphabetical,
                  child: Row(children: [
                    Icon(
                        _sortOrder == _FoodSortOrder.alphabetical
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context)?.sortAlphabetical ??
                        'Alphabetisch'),
                  ]),
                ),
                PopupMenuItem(
                  value: _FoodSortOrder.newest,
                  child: Row(children: [
                    Icon(
                        _sortOrder == _FoodSortOrder.newest
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context)?.sortNewest ?? 'Neueste'),
                  ]),
                ),
              ],
            ),
          // Manage database (only in authenticated mode)
          if (widget.dbService != null)
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: l.manageDatabase,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FoodDatabaseScreen(
                      dbService: widget.dbService!,
                    ),
                  ),
                );
                if (mounted) _loadMyFoods();
              },
            ),
          if (!_showManualEntry)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: AppLocalizations.of(context)?.barcodeScanTitle ??
                  'Barcode scannen',
              onPressed: _scanBarcode,
            ),
          if (!_showManualEntry && AppFeatures.nutritionLabelScan)
            IconButton(
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: l.scanNutritionLabel,
              onPressed: _scanNutritionLabel,
            ),
          if (!_showManualEntry)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showManualEntry = true;
                  _selectedFood = null;
                  _searchResults = [];
                });
              },
              icon: const Icon(Icons.edit),
              label: Text(l.manualEntry),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Food-Suche (nur wenn nicht manuell und noch nichts ausgewählt)
                  if (!_showManualEntry && _selectedFood == null) ...[
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: l.searchFood,
                        hintText: l.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _isSearching = false;
                                  });
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        // Bei OFF: Suche erst bei Enter, nicht beim Tippen
                        helperText: _useOpenFoodFacts
                            ? l.searchEnterHint
                            : null,
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        if (!_useOpenFoodFacts && widget.dbService != null) {
                          // Authenticated My DB: server-side full-text search
                          // (debounced). Empty query falls back to the preloaded
                          // list rendered via _displayedMyFoods.
                          setState(() {});
                          _searchDebounce?.cancel();
                          if (value.trim().isEmpty) {
                            setState(() {
                              _searchResults = [];
                              _isSearching = false;
                            });
                          } else {
                            _searchDebounce = Timer(
                                const Duration(milliseconds: 300),
                                () => _searchFoods(value));
                          }
                        } else if (!_useOpenFoodFacts) {
                          // Guest mode: search public/local foods
                          _searchFoods(value);
                        } else {
                          setState(
                              () {}); // Online: update suffixIcon, search on Enter
                        }
                      },
                      onSubmitted: (value) {
                        if (_useOpenFoodFacts || widget.dbService == null) {
                          _searchFoods(value);
                        } else if (widget.dbService != null) {
                          _searchDebounce?.cancel();
                          _searchFoods(value);
                        }
                      },
                    ),

                    const SizedBox(height: 8),

                    // Datenquelle-Toggle
                    Row(
                      children: [
                        ChoiceChip(
                          label: Text(l.myDatabase),
                          selected: !_useOpenFoodFacts,
                          onSelected: (_) => setState(() {
                            _useOpenFoodFacts = false;
                            _searchResults = [];
                          }),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Text('🌐'),
                          label: Text(l.onlineSearch),
                          selected: _useOpenFoodFacts,
                          onSelected: (_) => setState(() {
                            _useOpenFoodFacts = true;
                            _searchResults = [];
                          }),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Tag filter chips
                    if (!_useOpenFoodFacts &&
                        !_tagsLoading &&
                        _availableTags.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 8, right: 8, bottom: 8),
                          child: Wrap(
                            spacing: 8,
                            children: _availableTags.map((tag) {
                              final isSelected =
                                  _selectedTagSlugs.contains(tag.slug);
                              return FilterChip(
                                label: Text(tag.name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedTagSlugs.add(tag.slug);
                                    } else {
                                      _selectedTagSlugs.remove(tag.slug);
                                    }
                                  });
                                  // Online mode: re-search; My DB mode: _displayedMyFoods reacts
                                  if (_useOpenFoodFacts) {
                                    _searchFoods(_searchController.text);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],

                    // My DB preloaded list (authenticated) or online/guest search results
                    if (_isLoadingMyFoods || _isSearching)
                      const Center(child: CircularProgressIndicator())
                    else if (!_useOpenFoodFacts &&
                        widget.dbService != null &&
                        _searchController.text.trim().isEmpty) ...[
                      if (_myFoods.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.no_food,
                                    size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  l.foodDatabaseEmpty,
                                  style: TextStyle(color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_displayedMyFoods.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              l.noResults,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      else
                        Card(
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _displayedMyFoods.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final food = _displayedMyFoods[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    food.isPublic && food.isApproved
                                        ? '🌍'
                                        : food.isPublic
                                            ? '🕐'
                                            : '👤',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                                title: Text(food.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${food.calories.toInt()} kcal / 100${food.servingUnit ?? 'g'}'
                                      '${food.brand != null ? ' • ${food.brand}' : ''}'
                                      '${food.category != null ? ' • ${food.category}' : ''}',
                                    ),
                                    if (food.tags.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        children: food.tags.map((tag) {
                                          return Chip(
                                            label: Text(tag.name,
                                                style: const TextStyle(
                                                    fontSize: 11)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer,
                                            labelStyle: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondaryContainer),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.label_outline),
                                      tooltip:
                                          AppLocalizations.of(context)?.tags ??
                                              'Tags',
                                      onPressed: () =>
                                          _editFoodTagsInline(food),
                                    ),
                                    if (food.isPublic)
                                      const Icon(Icons.chevron_right)
                                    else
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        tooltip: l.options,
                                        onSelected: (action) async {
                                          if (action == 'use') {
                                            _selectFood(food);
                                          } else if (action == 'edit') {
                                            await _editFoodInSearch(food);
                                          } else if (action == 'delete') {
                                            await _deleteFoodInSearch(food);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'use',
                                            child: ListTile(
                                              leading: const Icon(
                                                  Icons.check_circle_outline),
                                              title: Text(l.useFood),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: ListTile(
                                              leading: const Icon(
                                                  Icons.edit_outlined),
                                              title: Text(l.edit),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red),
                                              title: Text(l.delete,
                                                  style: const TextStyle(
                                                      color: Colors.red)),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                onTap: () => _selectFood(food),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                    ]
                    // Online search or guest mode results
                    else if (_searchResults.isNotEmpty) ...[
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                l.resultsCount(_searchResults.length),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            const Divider(height: 1),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _searchResults.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final result = _searchResults[index];
                                final food = result.food;
                                final isOFF = food.source == 'OpenFoodFacts';
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      isOFF
                                          ? '🌐'
                                          : food.isPublic && food.isApproved
                                              ? '🌍'
                                              : food.isPublic
                                                  ? '🕐'
                                                  : '👤',
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                  title: Text(food.name),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${food.calories.toInt()} kcal / 100${food.servingUnit ?? 'g'}'
                                        '${food.brand != null ? ' • ${food.brand}' : ''}'
                                        '${food.category != null ? ' • ${food.category}' : ''}'
                                        '${food.source != null && !food.source!.contains('Custom') ? ' • ${food.source}' : ''}',
                                      ),
                                      if (food.tags.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 4,
                                          children: food.tags.map((tag) {
                                            return Chip(
                                              label: Text(tag.name,
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer,
                                              labelStyle: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSecondaryContainer),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.dbService != null)
                                        IconButton(
                                          icon: const Icon(Icons.label_outline),
                                          tooltip: AppLocalizations.of(context)
                                                  ?.tags ??
                                              'Tags',
                                          onPressed: () =>
                                              _editFoodTagsInline(food),
                                        ),
                                      if (isOFF ||
                                          food.isPublic ||
                                          widget.dbService == null)
                                        const Icon(Icons.chevron_right)
                                      else
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert),
                                          tooltip: l.options,
                                          onSelected: (action) async {
                                            if (action == 'use') {
                                              _selectFood(food,
                                                  micros: result.micros);
                                            } else if (action == 'edit') {
                                              await _editFoodInSearch(food);
                                            } else if (action == 'delete') {
                                              await _deleteFoodInSearch(food);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'use',
                                              child: ListTile(
                                                leading: const Icon(
                                                    Icons.check_circle_outline),
                                                title: Text(l.useFood),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: ListTile(
                                                leading: const Icon(
                                                    Icons.edit_outlined),
                                                title: Text(l.edit),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: ListTile(
                                                leading: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red),
                                                title: Text(l.delete,
                                                    style: const TextStyle(
                                                        color: Colors.red)),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  onTap: () =>
                                      _selectFood(food, micros: result.micros),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ]
                    // No-results fallback when a query is typed but nothing matched
                    else if (_searchController.text.trim().isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            l.noResults,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    ],
                  ],

                  // Gewähltes Food oder manuelle Eingabe
                  if (_selectedFood != null || _showManualEntry) ...[
                    // Info für manuelle Eingabe
                    if (_showManualEntry)
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.blue.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.addToDbTip,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l.addToDbTipBody,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (_selectedFood != null)
                      Card(
                        color: Colors.green.shade50,
                        child: ListTile(
                          leading: _selectedFood!.hasImage
                              ? SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: FoodThumbnailWidget(
                                    food: _selectedFood!,
                                    imageService: _imageService,
                                    imageCache: _imageCache,
                                  ),
                                )
                              : const Icon(Icons.check_circle,
                                  color: Colors.green),
                          title: Text(_selectedFood!.name),
                          subtitle: Text(
                            '${_selectedFood!.calories.toInt()} kcal / 100${_selectedFood!.servingUnit ?? 'g'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _selectedFood = null;
                                _nameController.clear();
                                _amountController.clear();
                                _caloriesController.clear();
                                _proteinController.clear();
                                _fatController.clear();
                                _carbsController.clear();
                              });
                            },
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Name (nur bei manueller Eingabe editierbar)
                    if (_showManualEntry)
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l.foodName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l.enterName;
                          }
                          return null;
                        },
                      ),

                    if (_showManualEntry) const SizedBox(height: 16),

                    // Menge & Einheit
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _amountController,
                            decoration: InputDecoration(
                              labelText: l.amount,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*[.,]?\d*')),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.enterAmount;
                              }
                              final amount = tryParseDouble(value);
                              if (amount == null || amount <= 0) {
                                return l.invalidAmount;
                              }
                              return null;
                            },
                            onChanged: (_) {
                              // Rebuild so the totals preview reflects the new amount.
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPortionSelector(),
                        ),
                      ],
                    ),

                    if (_showCookedNudge) ...[
                      const SizedBox(height: 8),
                      CookedWeightNudge(onSwitchToCooked: _switchToCookedUnit),
                    ],

                    // Let the user replace the generic factor with their own —
                    // most of the published spread in cooking yields is how a
                    // given person cooks, not measurement error.
                    if (_isCookedUnitSelected && _selectedFood != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openCookedCalibration,
                          icon: const Icon(Icons.straighten, size: 16),
                          label: Text(l.cookedCalibrateOpen,
                              style: const TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Totals preview: shows scaled nutrition so the user sees the
                    // effect of the current amount on the per-100g values below.
                    _buildTotalsPreview(),

                    const SizedBox(height: 16),

                    // How sure? — nutrition uncertainty (drives the daily band).
                    _buildEstimatePicker(),

                    const SizedBox(height: 16),

                    // Meal Type
                    DropdownButtonFormField<MealType>(
                      initialValue: _selectedMealType,
                      decoration: InputDecoration(
                        labelText: l.mealType,
                        border: const OutlineInputBorder(),
                      ),
                      items: MealType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Text(type.icon,
                                  style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Text(type.localizedName(l)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedMealType = value;
                          });
                        }
                      },
                    ),

                    if (_showManualEntry) ...[
                      const SizedBox(height: 16),

                      // Flüssigkeit (nur bei manuellen Einträgen)
                      SwitchListTile(
                        value: _isLiquid,
                        onChanged: (v) => setState(() => _isLiquid = v),
                        title: Text(l.foodIsLiquid),
                        subtitle: Text(l.foodIsLiquidHint),
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          _isLiquid
                              ? Icons.water_drop
                              : Icons.water_drop_outlined,
                          color: _isLiquid ? Colors.lightBlue : Colors.grey,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                    ],

                    // Hinweis: Nährwerte pro 100g/ml
                    if (_showManualEntry)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l.enterNutritionPer100,
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_showManualEntry) const SizedBox(height: 16),

                    // Nährwerte
                    Text(
                      l.nutritionalValues,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _caloriesController,
                            decoration: InputDecoration(
                              labelText: l.caloriesLabel,
                              suffixText: 'kcal',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.requiredField;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _proteinController,
                            decoration: InputDecoration(
                              labelText: l.proteinLabel,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.requiredField;
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fatController,
                            decoration: InputDecoration(
                              labelText: l.fatLabel,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.requiredField;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _carbsController,
                            decoration: InputDecoration(
                              labelText: l.carbsLabel,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.requiredField;
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Optional: Saturated Fat, Sugar, Fiber, Salt
                    Text(l.optionalSection,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _saturatedFatController,
                            decoration: InputDecoration(
                              labelText: l.nutrientSaturatedFat,
                              helperText: l.ofWhichFat,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                            validator: (value) {
                              // Only enforced for manually entered values;
                              // a selected DB food is trusted as-is.
                              if (_selectedFood != null) return null;
                              final sat = tryParseDouble(value);
                              final fat = tryParseDouble(_fatController.text);
                              if (sat != null && fat != null && sat > fat) {
                                return l.satFatExceedsFat;
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sugarController,
                            decoration: InputDecoration(
                              labelText: l.nutrientSugar,
                              helperText: l.ofWhichCarbs,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fiberController,
                            decoration: InputDecoration(
                              labelText: l.nutrientFiber,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sodiumController,
                            decoration: InputDecoration(
                              labelText: l.nutrientSalt,
                              suffixText: 'g',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            readOnly: _selectedFood != null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Zur Datenbank hinzufügen (manuell oder externes Ergebnis)
                    if (_showManualEntry ||
                        (_selectedFood != null &&
                            _selectedFood!.id.isEmpty)) ...[
                      ValueListenableBuilder(
                        valueListenable: _nameController,
                        builder: (context, nameValue, child) {
                          return ValueListenableBuilder(
                            valueListenable: _caloriesController,
                            builder: (context, caloriesValue, child) {
                              return ValueListenableBuilder(
                                valueListenable: _proteinController,
                                builder: (context, proteinValue, child) {
                                  return ValueListenableBuilder(
                                    valueListenable: _fatController,
                                    builder: (context, fatValue, child) {
                                      return ValueListenableBuilder(
                                        valueListenable: _carbsController,
                                        builder: (context, carbsValue, child) {
                                          final isEnabled = (_selectedFood !=
                                                      null &&
                                                  _selectedFood!.id.isEmpty) ||
                                              (nameValue.text.isNotEmpty &&
                                                  caloriesValue
                                                      .text.isNotEmpty &&
                                                  proteinValue
                                                      .text.isNotEmpty &&
                                                  fatValue.text.isNotEmpty &&
                                                  carbsValue.text.isNotEmpty);

                                          return Column(
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  onPressed: isEnabled
                                                      ? _saveFoodToDatabase
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.add_circle_outline),
                                                  label:
                                                      Text(l.saveToDatabase),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                l.saveFoodForFuture,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: (_selectedFood != null || _showManualEntry)
                  ? SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _saveEntry,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check),
                            label: Text(_isSaving ? l.saving : l.save),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rückgabe-Typ des Add-Food-Dialogs: das neue Lebensmittel plus
/// optional erfasste Mikronährstoffe (pro 100 g, DB-Spaltennamen als Schlüssel).
typedef AddFoodDialogResult = ({
  FoodItem food,
  Map<String, double> micros,
});

/// After a failed barcode lookup, offers to create a brand-new food carrying
/// [barcode]. On confirm it opens the "add to database" dialog (nutrition
/// entered manually or scanned from the label), persists the food to the
/// user's food DB, and returns the created [FoodItem] so the caller can log a
/// food entry for it. Returns null when the user cancels or the save fails.
Future<FoodItem?> createFoodFromScannedBarcode({
  required BuildContext context,
  required NeonDatabaseService dbService,
  required String barcode,
}) async {
  final l = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.barcodeNotFound),
      content: Text(l.barcodeCreatePrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.barcodeCreateFood),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  final result = await showDialog<AddFoodDialogResult>(
    context: context,
    builder: (_) => _AddFoodToDatabaseDialog(
      initialName: '',
      initialCalories: 0,
      initialProtein: 0,
      initialFat: 0,
      initialCarbs: 0,
      initialBarcode: barcode,
      showLabelScan: true,
      dbService: dbService,
    ),
  );
  if (result == null) return null;

  try {
    final service = FoodDatabaseService(dbService);
    final created = await service.createFood(result.food);
    if (result.food.tags.isNotEmpty) {
      await TagService(dbService).setFoodTags(created.id, result.food.tags);
    }
    if (result.micros.isNotEmpty) {
      final userId = dbService.userId;
      final jwt = dbService.jwt;
      if (userId != null && jwt != null) {
        await premiumFeatures.saveFoodDatabaseMicrosFromMap(
          foodId: created.id,
          userId: userId,
          micros100g: result.micros,
          authToken: jwt,
          apiUrl: NeonDatabaseService.dataApiUrl,
        );
      }
    }
    return created;
  } catch (e) {
    appLogger.w('⚠️ Create-food-from-barcode failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
      );
    }
    return null;
  }
}

/// Dialog zum Hinzufügen eines neuen Foods zur Datenbank
class _AddFoodToDatabaseDialog extends StatefulWidget {
  final String initialName;
  final double initialCalories;
  final double initialProtein;
  final double initialFat;
  final double initialCarbs;
  final double? initialFiber;
  final double? initialSugar;
  final double? initialSodium;
  final double? initialSaturatedFat;
  final String? initialCategory;
  final String? initialBrand;
  final List<FoodPortion> initialPortions;
  final Map<String, double> initialMicros;
  final bool initialIsLiquid;

  /// Pre-fills the barcode field — used by the "create food from an unknown
  /// barcode" flow so the scanned code is carried onto the new food row.
  final String? initialBarcode;

  /// When true (and the nutrition-label OCR feature is available), a
  /// "scan label" button is shown at the top to auto-fill the nutrition
  /// fields. Only enabled for the create-from-barcode flow.
  final bool showLabelScan;
  final NeonDatabaseService? dbService; // Nullable for guest mode

  const _AddFoodToDatabaseDialog({
    required this.initialName,
    required this.initialCalories,
    required this.initialProtein,
    required this.initialFat,
    required this.initialCarbs,
    this.initialFiber,
    this.initialSugar,
    this.initialSodium,
    this.initialSaturatedFat,
    this.initialCategory,
    this.initialBrand,
    this.initialPortions = const [],
    this.initialMicros = const {},
    this.initialIsLiquid = false,
    this.initialBarcode,
    this.showLabelScan = false,
    required this.dbService,
  });

  @override
  State<_AddFoodToDatabaseDialog> createState() =>
      _AddFoodToDatabaseDialogState();
}

class _AddFoodToDatabaseDialogState extends State<_AddFoodToDatabaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fiberController;
  late final TextEditingController _sugarController;
  late final TextEditingController _sodiumController;
  late final TextEditingController _saturatedFatController;
  late final TextEditingController _categoryController;
  late final TextEditingController _brandController;
  late final TextEditingController _barcodeController;
  final List<({TextEditingController name, TextEditingController amount})>
      _portionRows = [];
  bool _isPublic = false;
  bool _isLiquid = false;

  // Micronutrients (per 100 g) — keys = DB column names. Cloud-only.
  late Map<String, double> _micros;

  // Tags handling
  late List<Tag> _editingTags;
  late TagService _tagService;

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _isLiquid = widget.initialIsLiquid;
    _micros = Map<String, double>.from(widget.initialMicros);
    _nameController = TextEditingController(text: widget.initialName);
    _caloriesController =
        TextEditingController(text: widget.initialCalories.toStringAsFixed(0));
    _proteinController =
        TextEditingController(text: widget.initialProtein.toStringAsFixed(1));
    _fatController =
        TextEditingController(text: widget.initialFat.toStringAsFixed(1));
    _carbsController =
        TextEditingController(text: widget.initialCarbs.toStringAsFixed(1));
    _fiberController = TextEditingController(
        text: widget.initialFiber != null ? _fmt(widget.initialFiber!) : '');
    _sugarController = TextEditingController(
        text: widget.initialSugar != null ? _fmt(widget.initialSugar!) : '');
    _sodiumController = TextEditingController(
        text: widget.initialSodium != null ? _fmt(widget.initialSodium!) : '');
    _saturatedFatController = TextEditingController(
        text: widget.initialSaturatedFat != null
            ? _fmt(widget.initialSaturatedFat!)
            : '');
    _categoryController =
        TextEditingController(text: widget.initialCategory ?? '');
    _brandController = TextEditingController(text: widget.initialBrand ?? '');
    _barcodeController =
        TextEditingController(text: widget.initialBarcode ?? '');
    // Portionszeilen aus initialPortions übernehmen
    for (final p in widget.initialPortions) {
      _portionRows.add((
        name: TextEditingController(text: p.name),
        amount: TextEditingController(
            text: p.amountG % 1 == 0
                ? p.amountG.toInt().toString()
                : p.amountG.toString()),
      ));
    }

    // Initialize tag service (only if authenticated)
    if (widget.dbService != null) {
      _tagService = TagService(widget.dbService!);
    }
    _editingTags = [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _saturatedFatController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _barcodeController.dispose();
    for (final row in _portionRows) {
      row.name.dispose();
      row.amount.dispose();
    }
    super.dispose();
  }

  Widget _nutrientField({
    required TextEditingController controller,
    required String label,
    required String unit,
    bool isRequired = false,
    String? Function(String?)? extraValidator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        suffixText: unit,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      validator: (v) {
        if (isRequired) {
          if (v == null || v.trim().isEmpty) return 'Pflichtfeld';
          if (tryParseDouble(v) == null) return 'Ungültig';
        } else if (v != null &&
            v.trim().isNotEmpty &&
            tryParseDouble(v) == null) {
          return 'Ungültig';
        }
        return extraValidator?.call(v);
      },
    );
  }

  /// Runs the nutrition-label OCR scan (Premium, mobile) and pre-fills the
  /// form's nutrition fields with the recognised per-100 g values. Leaves the
  /// barcode and any field the scan couldn't read untouched.
  Future<void> _scanLabelIntoForm() async {
    if (!AppFeatures.nutritionLabelScan) return;
    final result = await premiumFeatures.scanNutritionLabel(
      context: context,
      preferredLocale: Localizations.localeOf(context),
    );
    if (!mounted || result == null) return;

    String fmt(double? v, {int digits = 1}) =>
        v == null ? '' : v.toStringAsFixed(digits);

    setState(() {
      if (result.productName != null && result.productName!.isNotEmpty) {
        _nameController.text = result.productName!;
      }
      if (result.caloriesPer100g != null) {
        _caloriesController.text = fmt(result.caloriesPer100g, digits: 0);
      }
      if (result.proteinPer100g != null) {
        _proteinController.text = fmt(result.proteinPer100g);
      }
      if (result.fatPer100g != null) {
        _fatController.text = fmt(result.fatPer100g);
      }
      if (result.carbsPer100g != null) {
        _carbsController.text = fmt(result.carbsPer100g);
      }
      if (result.satFatPer100g != null) {
        _saturatedFatController.text = fmt(result.satFatPer100g);
      }
      if (result.sugarPer100g != null) {
        _sugarController.text = fmt(result.sugarPer100g);
      }
      if (result.fiberPer100g != null) {
        _fiberController.text = fmt(result.fiberPer100g);
      }
      if (result.saltPer100g != null) {
        _sodiumController.text = fmt(result.saltPer100g, digits: 2);
      }
    });

    if (result.warnings.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warnings.join(' ')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final portions = _portionRows
        .where((r) => r.name.text.trim().isNotEmpty && r.amount.text.isNotEmpty)
        .map((r) => FoodPortion(
              name: r.name.text.trim(),
              amountG: tryParseDouble(r.amount.text) ?? 0,
            ))
        .where((p) => p.amountG > 0)
        .toList();

    // Check for duplicate portion names
    final portionNames = portions.map((p) => p.name.toLowerCase()).toList();
    final uniqueNames = portionNames.toSet();
    if (portionNames.length != uniqueNames.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ Portionen dürfen keine doppelten Namen haben')),
      );
      return;
    }

    final food = FoodItem(
      id: '',
      userId: null,
      name: _nameController.text,
      calories: parseDouble(_caloriesController.text),
      protein: parseDouble(_proteinController.text),
      fat: parseDouble(_fatController.text),
      carbs: parseDouble(_carbsController.text),
      fiber: tryParseDouble(_fiberController.text),
      sugar: tryParseDouble(_sugarController.text),
      sodium: tryParseDouble(_sodiumController.text),
      saturatedFat: tryParseDouble(_saturatedFatController.text),
      servingSize: null,
      servingUnit: null,
      portions: portions,
      category:
          _categoryController.text.isNotEmpty ? _categoryController.text : null,
      brand: _brandController.text.isNotEmpty ? _brandController.text : null,
      barcode: _barcodeController.text.trim().isNotEmpty
          ? _barcodeController.text.trim()
          : null,
      isPublic: _isPublic,
      isLiquid: _isLiquid,
      isApproved: false,
      tags: _editingTags, // Pass tags back via FoodItem
      source: 'Custom',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop<AddFoodDialogResult>((food: food, micros: _micros));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      scrollable: true,
      title: const Text('Zur Datenbank hinzufügen'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Optional: pre-fill the nutrition fields by scanning the label
            // (Premium / mobile). Only offered for the create-from-barcode flow.
            if (widget.showLabelScan && AppFeatures.nutritionLabelScan) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _scanLabelIntoForm,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(l.scanNutritionLabel),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alle Werte sind pro 100g bzw. 100ml',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Erforderlich';
                }
                return null;
              },
            ),

            const SizedBox(height: 12),

            // Kategorie
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Kategorie (optional)',
                hintText: 'z.B. Obst, Gemüse, Fleisch',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            // Marke
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Marke (optional)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            // Barcode
            TextFormField(
              controller: _barcodeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)?.barcodeField ??
                    'Barcode (optional)',
                hintText: AppLocalizations.of(context)?.barcodeHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: AppLocalizations.of(context)?.barcodeScanTitle,
                  onPressed: () async {
                    final scanned = await showBarcodeScannerSheet(context);
                    if (scanned != null && mounted) {
                      setState(() => _barcodeController.text = scanned);
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Flüssigkeit
            SwitchListTile(
              value: _isLiquid,
              onChanged: (v) => setState(() => _isLiquid = v),
              title: const Text('Flüssigkeit'),
              subtitle: const Text('Wird in ml statt g eingegeben'),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                _isLiquid ? Icons.water_drop : Icons.water_drop_outlined,
                color: _isLiquid ? Colors.lightBlue : Colors.grey,
              ),
            ),

            // Portionsgrößen
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Portionsgrößen',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _portionRows.add((
                        name: TextEditingController(),
                        amount: TextEditingController(),
                      ));
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Hinzufügen'),
                ),
              ],
            ),
            if (_portionRows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Keine Portionen definiert – Eingabe immer in g/ml',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              )
            else
              ...List.generate(_portionRows.length, (i) {
                final row = _portionRows[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: row.name,
                          decoration: const InputDecoration(
                            labelText: 'Bezeichnung',
                            hintText: 'z.B. 1 Scheibe',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: row.amount,
                          decoration: const InputDecoration(
                            labelText: 'Gramm',
                            suffixText: 'g',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () {
                          setState(() {
                            row.name.dispose();
                            row.amount.dispose();
                            _portionRows.removeAt(i);
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),

            // ── Nährwerte (pro 100 g/ml) ─────────────────────────────────
            const SizedBox(height: 16),
            Text(
              'Nährwerte (pro 100 ${_isLiquid ? 'ml' : 'g'})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _nutrientField(
                  controller: _caloriesController,
                  label: 'Kalorien',
                  unit: 'kcal',
                  isRequired: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _nutrientField(
                  controller: _proteinController,
                  label: 'Protein',
                  unit: 'g',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _nutrientField(
                  controller: _fatController,
                  label: 'Fett',
                  unit: 'g',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _nutrientField(
                  controller: _saturatedFatController,
                  label: 'davon ges. Fett',
                  unit: 'g',
                  extraValidator: (v) {
                    final sat = tryParseDouble(v);
                    final fat = tryParseDouble(_fatController.text);
                    if (sat != null && fat != null && sat > fat) {
                      return l.satFatExceedsFat;
                    }
                    return null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _nutrientField(
                  controller: _carbsController,
                  label: 'Kohlenhydrate',
                  unit: 'g',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _nutrientField(
                  controller: _sugarController,
                  label: 'davon Zucker',
                  unit: 'g',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _nutrientField(
                  controller: _fiberController,
                  label: 'Ballaststoffe',
                  unit: 'g',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _nutrientField(
                  controller: _sodiumController,
                  label: 'Salz',
                  unit: 'g',
                ),
              ),
            ]),

            // ── Mikronährstoffe (Cloud, pro 100 g) ──────────────────────
            if (AppFeatures.microNutrients) ...[
              const SizedBox(height: 16),
              Text(
                'Mikronährstoffe (pro 100 ${_isLiquid ? 'ml' : 'g'})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              premiumFeatures.buildFoodMicrosInlineEditor(
                initialMicros: widget.initialMicros,
                onChanged: (m) => _micros = m,
              ),
            ],

            const SizedBox(height: 12),

            // Öffentlich / Privat
            SwitchListTile(
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: const Text('Für alle Nutzer sichtbar'),
              subtitle: Text(
                _isPublic
                    ? 'Jeder kann dieses Lebensmittel in der Suche finden'
                    : 'Nur du siehst diesen Eintrag',
              ),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                _isPublic ? Icons.public : Icons.lock_outline,
                color: _isPublic ? Colors.green : Colors.grey,
              ),
            ),

            const SizedBox(height: 16),

            // Tags
            Text(
              l.tags,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TagEditor(
              tags: _editingTags,
              onChanged: (tags) => setState(() => _editingTags = tags),
              tagService: _tagService,
              readOnly: false,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Hinzufügen'),
        ),
      ],
    );
  }
}

/// Small label+value widget for the totals preview card.
class _PreviewMacro extends StatelessWidget {
  final String label;
  final String value;
  const _PreviewMacro(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
