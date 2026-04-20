import 'package:flutter/material.dart';
import '../utils/number_utils.dart';
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
import '../services/food_search_service.dart';
import '../services/local_data_service.dart';
import '../services/app_logger.dart';
import '../services/anonymous_auth_service.dart';
import '../app_config.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';
import '../widgets/food_thumbnail_widget.dart';
import '../widgets/tag_editor.dart';
import 'food_database_screen.dart';

/// Screen zum Hinzufügen eines Food-Entries
///
/// Workflow:
/// 1. Suche Food in Datenbank (optional)
/// 2. Wähle Menge & Einheit
/// 3. Wähle Meal Type
/// 4. Speichere Entry
class AddFoodEntryScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime? selectedDate;
  final MealType? initialMealType;
  final FoodItem? preselectedFood;

  const AddFoodEntryScreen({
    super.key,
    this.dbService,
    this.selectedDate,
    this.initialMealType,
    this.preselectedFood,
  });
  
  @override
  State<AddFoodEntryScreen> createState() => _AddFoodEntryScreenState();
}

MealType _mealTypeForCurrentTime() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 10) return MealType.breakfast;   // 05–10 Uhr
  if (hour >= 10 && hour < 14) return MealType.lunch;      // 10–14 Uhr
  if (hour >= 14 && hour < 18) return MealType.snack;      // 14–18 Uhr
  return MealType.dinner;                                   // 18–05 Uhr
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
  FoodPortion? _selectedPortion;  // null = custom g/ml Eingabe
  String _customUnit = 'g';       // 'g' oder 'ml' wenn _selectedPortion == null
  bool _isSaving = false;
  bool _useOpenFoodFacts = false;
  bool _isLiquid = false;

  // Guest mode: optional anonymous JWT for public food DB access
  NeonDatabaseService? _anonDbService;
  late FoodImageService _imageService;
  final Map<String, String?> _imageCache = {};

  // Tag filtering
  late TagService _tagService;
  List<Tag> _availableTags = [];
  final Set<String> _selectedTagSlugs = {};  // tag slugs selected for filtering
  bool _tagsLoading = true;

  @override
  void initState() {
    super.initState();
    // Only initialize DB-dependent services if dbService is available (not guest mode)
    if (widget.dbService != null) {
      _imageService = FoodImageService(widget.dbService!);
      _tagService = TagService(widget.dbService!);
      _loadAvailableTags();  // Load tags for filtering
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
      appLogger.w('⚠️ Guest mode: failed to initialize anonymous DB access: $e');
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
          final items = await FoodDatabaseService(widget.dbService!).searchFoods(
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
              final items = await FoodDatabaseService(_anonDbService!).searchFoods(
                query,
                limit: 20,
              );
              results.addAll(items.map((f) => FoodSearchResult(food: f)));
              appLogger.d('🔍 Found ${items.length} public foods from anonymous DB');
            } catch (e) {
              appLogger.w('⚠️ Anonymous food search failed: $e');
            }
          }

          // Search locally stored guest foods
          try {
            final guestFoods = await LocalDataService.instance.searchGuestFoods(query);
            results.addAll(guestFoods.map((f) => FoodSearchResult(food: f)));
            appLogger.d('🔍 Found ${guestFoods.length} guest foods from local storage');
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
          _customUnit =
              (unit.startsWith('ml') || food.isLiquid) ? 'ml' : 'g';
          _amountController.text = food.servingSize != null
              ? food.servingSize!.toInt().toString()
              : '100';
        }
      }

      // Verberge Suchergebnisse
      _searchResults = [];
      _showManualEntry = false;
    });
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

  /// Grams equivalent of the current amount+unit (used for scaling per-100g values).
  /// For portions: amount × portion.amountG. For custom g/ml units: amount directly.
  double _currentGrams() {
    final rawAmount = tryParseDouble(_amountController.text) ?? 0;
    if (rawAmount <= 0) return 0;
    return _selectedPortion != null
        ? rawAmount * _selectedPortion!.amountG
        : rawAmount;
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
  Widget _buildTotalsPreview() {
    final totals = _computeTotals();
    final rawAmount = tryParseDouble(_amountController.text) ?? 0;
    if (rawAmount <= 0) return const SizedBox.shrink();

    final amountStr = rawAmount == rawAmount.truncateToDouble()
        ? rawAmount.toInt().toString()
        : rawAmount.toStringAsFixed(1);
    final unitLabel = _selectedPortion?.name ?? _customUnit;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gesamt für $amountStr$unitLabel:',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _PreviewMacro('kcal', totals['calories']!.toStringAsFixed(0)),
                _PreviewMacro('P', '${totals['protein']!.toStringAsFixed(1)}g'),
                _PreviewMacro('F', '${totals['fat']!.toStringAsFixed(1)}g'),
                _PreviewMacro('KH', '${totals['carbs']!.toStringAsFixed(1)}g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dropdown zur Portionsauswahl (benannte Portionen + g/ml)
  Widget _buildPortionSelector() {
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
    final currentKey =
        _selectedPortion != null ? 'p:${_selectedPortion!.name}' : _customUnit;

    final items = <DropdownMenuItem<String>>[];

    // Benannte Portionen
    for (final p in portions) {
      items.add(DropdownMenuItem(
        value: 'p:${p.name}',
        child: Text('${p.name} (${p.amountG % 1 == 0 ? p.amountG.toInt() : p.amountG}g)'),
      ));
    }

    // Immer: g und ml
    items.add(const DropdownMenuItem(value: 'g', child: Text('g')));
    items.add(const DropdownMenuItem(value: 'ml', child: Text('ml')));

    return DropdownButtonFormField<String>(
      initialValue: currentKey,
      decoration: const InputDecoration(
        labelText: 'Einheit',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          if (value.startsWith('p:')) {
            final name = value.substring(2);
            _selectedPortion =
                food?.portions.firstWhere((p) => p.name == name);
            _amountController.text = '1';
          } else {
            _selectedPortion = null;
            _customUnit = value;
            if (food?.servingSize != null && value == 'g') {
              _amountController.text = food!.servingSize!.toInt().toString();
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
      final userId = dbService?.userId ?? '';  // Guest mode: empty userId

      final rawAmount = parseDouble(_amountController.text);

      // Calculate amountMl for liquid foods
      double? amountMl;
      if (_isLiquid) {
        if (_selectedPortion != null) {
          // Portion: amount * portion.amountG (treating G as ml for liquid foods)
          amountMl = rawAmount * _selectedPortion!.amountG;
        } else if (_customUnit == 'ml') {
          // Direct ml entry
          amountMl = rawAmount;
        }
      }

      // Nutrition controllers are ALWAYS per-100g (both manual entry and selected
      // food). Scale to totals by actual grams (portion amount × amountG, or
      // raw amount for g/ml).
      final grams = _selectedPortion != null
          ? rawAmount * _selectedPortion!.amountG
          : rawAmount;
      final scale = grams / 100.0;

      final entry = FoodEntry(
        id: '',  // Wird von DB generiert
        userId: userId,
        foodId: (_selectedFood?.id.isNotEmpty == true) ? _selectedFood!.id : null,
        entryDate: widget.selectedDate ?? DateTime.now(),
        mealType: _selectedMealType,
        name: _nameController.text,
        amount: rawAmount,
        unit: _selectedPortion?.name ?? _customUnit,
        calories: parseDouble(_caloriesController.text) * scale,
        protein: parseDouble(_proteinController.text)  * scale,
        fat:     parseDouble(_fatController.text)       * scale,
        carbs:   parseDouble(_carbsController.text)     * scale,
        fiber:   tryParseDouble(_fiberController.text) != null ? parseDouble(_fiberController.text) * scale : null,
        sugar:   tryParseDouble(_sugarController.text) != null ? parseDouble(_sugarController.text) * scale : null,
        sodium:  tryParseDouble(_sodiumController.text) != null ? parseDouble(_sodiumController.text) * scale : null,
        saturatedFat: tryParseDouble(_saturatedFatController.text) != null ? parseDouble(_saturatedFatController.text) * scale : null,
        isLiquid: _isLiquid,
        amountMl: amountMl,
        isMeal: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await SyncService.instance.createFoodEntry(entry);
      // Add the server entity (real id) or the optimistic entry (queued offline).
      final effective = saved ?? entry;
      DataStore.instance.addFoodEntry(effective);

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

    if (!isExternal && !_formKey.currentState!.validate()) return;

    // Zeige Dialog mit erweiterten Optionen
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => _AddFoodToDatabaseDialog(
        initialName: _nameController.text,
        initialCalories: initialCalories,
        initialProtein: initialProtein,
        initialFat: initialFat,
        initialCarbs: initialCarbs,
        initialCategory: _selectedFood?.category,
        initialBrand: _selectedFood?.brand,
        initialPortions: _selectedFood?.portions ?? [],
        dbService: widget.dbService!,
      ),
    );

    if (result != null) {
      try {
        final service = FoodDatabaseService(widget.dbService!);
        final created = await service.createFood(result);

        // Save tags if any were added
        if (result.tags.isNotEmpty) {
          appLogger.d('💾 Saving ${result.tags.length} tags for newly created food');
          final tagService = TagService(widget.dbService!);
          await tagService.setFoodTags(created.id, result.tags);
        }

        if (mounted) {
          // Preserve the user's current amount (in grams) so returning from the
          // dialog doesn't reset it. _selectFood picks a matching portion if one
          // exists, otherwise falls back to grams.
          final prevGrams = _currentGrams();
          _selectFood(
            created,
            preservedAmountG: prevGrams > 0 ? prevGrams : null,
          );
          final lCtx = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lCtx.foodAdded(created.name)),
              backgroundColor: Colors.green,
            ),
          );
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

    if (!isExternal && !_formKey.currentState!.validate()) return;

    // Show dialog to create food
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => _AddFoodToDatabaseDialog(
        initialName: _nameController.text,
        initialCalories: initialCalories,
        initialProtein: initialProtein,
        initialFat: initialFat,
        initialCarbs: initialCarbs,
        initialCategory: _selectedFood?.category,
        initialBrand: _selectedFood?.brand,
        initialPortions: _selectedFood?.portions ?? [],
        dbService: null,  // No DB service in guest mode
      ),
    );

    if (result != null) {
      try {
        // Save locally
        final saved = await LocalDataService.instance.saveGuestFood(result);
        final prevGrams = _currentGrams();
        _selectFood(
          saved,
          preservedAmountG: prevGrams > 0 ? prevGrams : null,
        );

        if (mounted) {
          final lCtx = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${lCtx.foodAdded(saved.name)} (lokal gespeichert)'),
              backgroundColor: Colors.green,
            ),
          );
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
      builder: (context) => FoodEditDialog(food: food, dbService: widget.dbService!),
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
        // Suchergebnisse neu laden
        _searchFoods(_searchController.text);
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
        _searchFoods(_searchController.text);
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
    showDialog(
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
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.addFoodScreenTitle),
        actions: [
          // Database button (only in authenticated mode)
          if (widget.dbService != null)
            IconButton(
              icon: const Icon(Icons.storage_outlined),
              tooltip: 'Meine Datenbank',
              onPressed: () async {
                final food = await Navigator.of(context).push<FoodItem>(
                  MaterialPageRoute(
                    builder: (context) => FoodDatabaseScreen(
                      dbService: widget.dbService!,
                      pickerMode: true,
                    ),
                  ),
                );
                if (food != null) {
                  _selectFood(food);
                }
              },
            ),
          if (!_showManualEntry && AppFeatures.nutritionLabelScan)
            IconButton(
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Etikett scannen',
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
              label: const Text('Manuell'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Food-Suche (nur wenn nicht manuell)
            if (!_showManualEntry) ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Lebensmittel suchen',
                  hintText: 'z.B. Apfel, Reis, Hähnchen...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                            });
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  // Bei OFF: Suche erst bei Enter, nicht beim Tippen
                  helperText: _useOpenFoodFacts ? 'Enter drücken zum Suchen' : null,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  // Eigene DB: sofort suchen; OFF: nur UI-Update (kein Request)
                  if (!_useOpenFoodFacts) {
                    _searchFoods(value);
                  } else {
                    setState(() {}); // Nur für suffixIcon-Update
                  }
                },
                onSubmitted: (value) {
                  _searchFoods(value);
                },
              ),

              const SizedBox(height: 8),

              // Datenquelle-Toggle
              Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Eigene DB'),
                      selected: !_useOpenFoodFacts,
                      onSelected: (_) => setState(() {
                        _useOpenFoodFacts = false;
                        _searchResults = [];
                        if (_searchController.text.isNotEmpty) {
                          _searchFoods(_searchController.text);
                        }
                      }),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Text('🌐'),
                      label: const Text('Online-Suche'),
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
              if (!_useOpenFoodFacts && !_tagsLoading && _availableTags.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      children: _availableTags.map((tag) {
                        final isSelected = _selectedTagSlugs.contains(tag.slug);
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
                            // Re-search with new filters
                            _searchFoods(_searchController.text);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],

              // Suchergebnisse
              if (_isSearching)
                const Center(child: CircularProgressIndicator())
              else if (_searchResults.isNotEmpty) ...[
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${_searchResults.length} Ergebnisse',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const Divider(height: 1),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                        label: Text(
                                          tag.name,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                        labelStyle: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ]
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Tag button for adding/editing tags (only in authenticated mode)
                                if (widget.dbService != null)
                                  IconButton(
                                    icon: const Icon(Icons.label_outline),
                                    tooltip: AppLocalizations.of(context)?.tags ?? 'Tags',
                                    onPressed: () => _editFoodTagsInline(food),
                                  ),
                                // Menu or chevron for other actions (only show menu in authenticated mode for own foods)
                                if (isOFF || food.isPublic || widget.dbService == null)
                                  const Icon(Icons.chevron_right)
                                else
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    tooltip: 'Optionen',
                                    onSelected: (action) async {
                                      if (action == 'use') {
                                        _selectFood(food, micros: result.micros);
                                      } else if (action == 'edit') {
                                        await _editFoodInSearch(food);
                                      } else if (action == 'delete') {
                                        await _deleteFoodInSearch(food);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'use',
                                        child: ListTile(
                                          leading: Icon(Icons.check_circle_outline),
                                          title: Text('Verwenden'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: ListTile(
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Bearbeiten'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          leading: Icon(Icons.delete_outline,
                                              color: Colors.red),
                                          title: Text('Löschen',
                                              style: TextStyle(color: Colors.red)),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            onTap: () => _selectFood(food, micros: result.micros),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tipp: Zur Datenbank hinzufügen',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Nach dem Ausfüllen kannst du dieses Lebensmittel für die Zukunft speichern!',
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
                        : const Icon(Icons.check_circle, color: Colors.green),
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
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bitte Name eingeben';
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
                      decoration: const InputDecoration(
                        labelText: 'Menge',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Bitte Menge eingeben';
                        }
                        final amount = tryParseDouble(value);
                        if (amount == null || amount <= 0) {
                          return 'Ungültige Menge';
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

              const SizedBox(height: 12),

              // Totals preview: shows scaled nutrition so the user sees the
              // effect of the current amount on the per-100g values below.
              _buildTotalsPreview(),

              const SizedBox(height: 16),

              // Meal Type
              DropdownButtonFormField<MealType>(
                initialValue: _selectedMealType,
                decoration: const InputDecoration(
                  labelText: 'Mahlzeit',
                  border: OutlineInputBorder(),
                ),
                items: MealType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Text(type.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(type.displayName),
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
                    _isLiquid ? Icons.water_drop : Icons.water_drop_outlined,
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
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Alle Nährwerte pro 100g bzw. 100ml angeben',
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
                'Nährwerte',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      decoration: const InputDecoration(
                        labelText: 'Kalorien',
                        suffixText: 'kcal',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Erforderlich';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _proteinController,
                      decoration: const InputDecoration(
                        labelText: 'Protein',
                        suffixText: 'g',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Erforderlich';
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
                      decoration: const InputDecoration(
                        labelText: 'Fett',
                        suffixText: 'g',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Erforderlich';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsController,
                      decoration: const InputDecoration(
                        labelText: 'Kohlenhydrate',
                        suffixText: 'g',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Erforderlich';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Optional: Saturated Fat, Sugar, Fiber, Salt
              Text('Optional', style: Theme.of(context).textTheme.titleSmall),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: _selectedFood != null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Zur Datenbank hinzufügen (manuell oder externes Ergebnis)
              if (_showManualEntry || (_selectedFood != null && _selectedFood!.id.isEmpty)) ...[
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
                                    final isEnabled =
                                        (_selectedFood != null && _selectedFood!.id.isEmpty) ||
                                        (nameValue.text.isNotEmpty &&
                                            caloriesValue.text.isNotEmpty &&
                                            proteinValue.text.isNotEmpty &&
                                            fatValue.text.isNotEmpty &&
                                            carbsValue.text.isNotEmpty);
                                    
                                    return Column(
                                      children: [
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: isEnabled ? _saveFoodToDatabase : null,
                                            icon: const Icon(Icons.add_circle_outline),
                                            label: const Text('Zur Datenbank hinzufügen'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.all(16),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Speichere dieses Lebensmittel für zukünftige Verwendung',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade600,
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
              
              // Speichern Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveEntry,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'Speichere...' : 'Speichern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog zum Hinzufügen eines neuen Foods zur Datenbank
class _AddFoodToDatabaseDialog extends StatefulWidget {
  final String initialName;
  final double initialCalories;
  final double initialProtein;
  final double initialFat;
  final double initialCarbs;
  final String? initialCategory;
  final String? initialBrand;
  final List<FoodPortion> initialPortions;
  final NeonDatabaseService? dbService;  // Nullable for guest mode

  const _AddFoodToDatabaseDialog({
    required this.initialName,
    required this.initialCalories,
    required this.initialProtein,
    required this.initialFat,
    required this.initialCarbs,
    this.initialCategory,
    this.initialBrand,
    this.initialPortions = const [],
    required this.dbService,
  });
  
  @override
  State<_AddFoodToDatabaseDialog> createState() => _AddFoodToDatabaseDialogState();
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
  final List<({TextEditingController name, TextEditingController amount})> _portionRows = [];
  bool _isPublic = false;
  bool _isLiquid = false;

  // Tags handling
  late List<Tag> _editingTags;
  late TagService _tagService;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _caloriesController = TextEditingController(text: widget.initialCalories.toStringAsFixed(0));
    _proteinController = TextEditingController(text: widget.initialProtein.toStringAsFixed(1));
    _fatController = TextEditingController(text: widget.initialFat.toStringAsFixed(1));
    _carbsController = TextEditingController(text: widget.initialCarbs.toStringAsFixed(1));
    _fiberController = TextEditingController();
    _sugarController = TextEditingController();
    _sodiumController = TextEditingController();
    _saturatedFatController = TextEditingController();
    _categoryController = TextEditingController(text: widget.initialCategory ?? '');
    _brandController = TextEditingController(text: widget.initialBrand ?? '');
    // Portionszeilen aus initialPortions übernehmen
    for (final p in widget.initialPortions) {
      _portionRows.add((
        name: TextEditingController(text: p.name),
        amount: TextEditingController(
            text: p.amountG % 1 == 0 ? p.amountG.toInt().toString() : p.amountG.toString()),
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
    for (final row in _portionRows) {
      row.name.dispose();
      row.amount.dispose();
    }
    super.dispose();
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
        const SnackBar(content: Text('⚠️ Portionen dürfen keine doppelten Namen haben')),
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
      category: _categoryController.text.isNotEmpty ? _categoryController.text : null,
      brand: _brandController.text.isNotEmpty ? _brandController.text : null,
      barcode: null,
      isPublic: _isPublic,
      isLiquid: _isLiquid,
      isApproved: false,
      tags: _editingTags,  // Pass tags back via FoodItem
      source: 'Custom',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop(food);
  }
  
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: const Text('Zur Datenbank hinzufügen'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
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
