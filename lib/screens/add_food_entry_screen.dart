import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../models/food_item.dart';
import '../models/food_search_result.dart';
import '../models/food_entry.dart';
import '../models/food_portion.dart';
import '../services/food_database_service.dart';
import '../services/neon_database_service.dart';
import '../services/food_image_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/food_search_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../widgets/food_thumbnail_widget.dart';
import 'food_database_screen.dart';

/// Screen zum Hinzufügen eines Food-Entries
///
/// Workflow:
/// 1. Suche Food in Datenbank (optional)
/// 2. Wähle Menge & Einheit
/// 3. Wähle Meal Type
/// 4. Speichere Entry
class AddFoodEntryScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final DateTime? selectedDate;
  final MealType? initialMealType;
  final FoodItem? preselectedFood;

  const AddFoodEntryScreen({
    super.key,
    required this.dbService,
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
  late FoodImageService _imageService;
  final Map<String, String?> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _imageService = FoodImageService(widget.dbService);
    if (widget.initialMealType != null) {
      _selectedMealType = widget.initialMealType!;
    }
    // Pre-select food if provided from FoodDetailScreen
    if (widget.preselectedFood != null) {
      _selectFood(widget.preselectedFood!);
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
  
  /// Suche Foods in Datenbank
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
      final List<FoodSearchResult> results;
      if (_useOpenFoodFacts) {
        results = await FoodSearchService().search(query);
      } else {
        final items = await FoodDatabaseService(widget.dbService).searchFoods(query, limit: 20);
        results = items.map((f) => FoodSearchResult(food: f)).toList();
      }

      setState(() {
        _searchResults = results;
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
  
  /// Wähle Food aus Suchergebnissen
  void _selectFood(FoodItem food, {Map<String, double> micros = const {}}) {
    setState(() {
      _selectedFood = food;
      _selectedMicros = micros;
      _nameController.text = food.name;
      
      // Portionsgröße vorauswählen
      if (food.portions.isNotEmpty) {
        _selectedPortion = food.portions.first;
        _amountController.text = '1';
      } else {
        _selectedPortion = null;
        // Einheit aus servingUnit ableiten, aber ml wenn Flüssigkeit
        final unit = food.servingUnit ?? 'g';
        _customUnit = (unit.startsWith('ml') || food.isLiquid) ? 'ml' : 'g';
        _amountController.text =
            food.servingSize != null ? food.servingSize!.toInt().toString() : '100';
      }

      _isLiquid = food.isLiquid;

      // Berechne Nährwerte für Portion
      if (_amountController.text.isNotEmpty) {
        _calculateNutrition();
      }

      // Verberge Suchergebnisse
      _searchResults = [];
      _showManualEntry = false;
    });
  }
  
  /// Berechne Nährwerte basierend auf Menge
  void _calculateNutrition() {
    if (_selectedFood == null) return;
    if (_amountController.text.isEmpty) return;

    final rawAmount = double.tryParse(_amountController.text);
    if (rawAmount == null || rawAmount <= 0) return;

    final grams = _selectedPortion != null
        ? rawAmount * _selectedPortion!.amountG
        : rawAmount;

    final nutrition = _selectedFood!.calculateNutrition(grams);

    setState(() {
      _caloriesController.text = nutrition['calories']!.toStringAsFixed(0);
      _proteinController.text = nutrition['protein']!.toStringAsFixed(1);
      _fatController.text = nutrition['fat']!.toStringAsFixed(1);
      _carbsController.text = nutrition['carbs']!.toStringAsFixed(1);
      if (nutrition['fiber'] != null) {
        _fiberController.text = nutrition['fiber']!.toStringAsFixed(1);
      }
      if (nutrition['sugar'] != null) {
        _sugarController.text = nutrition['sugar']!.toStringAsFixed(1);
      }
      if (nutrition['sodium'] != null) {
        _sodiumController.text = nutrition['sodium']!.toStringAsFixed(1);
      }
      if (nutrition['saturated_fat'] != null) {
        _saturatedFatController.text = nutrition['saturated_fat']!.toStringAsFixed(1);
      }
    });
  }
  
  /// Dropdown zur Portionsauswahl (benannte Portionen + g/ml)
  Widget _buildPortionSelector() {
    final food = _selectedFood;
    final portions = food?.portions ?? [];

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
          _calculateNutrition();
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
      final userId = widget.dbService.userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      final rawAmount = double.parse(_amountController.text);

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

      // For manual entry: fields are per-100g, scale to total
      // For food-from-DB: _calculateNutrition() already filled controllers with totals
      final scale = _selectedFood == null ? rawAmount / 100.0 : 1.0;

      final entry = FoodEntry(
        id: '',  // Wird von DB generiert
        userId: userId,
        foodId: (_selectedFood?.id.isNotEmpty == true) ? _selectedFood!.id : null,
        entryDate: widget.selectedDate ?? DateTime.now(),
        mealType: _selectedMealType,
        name: _nameController.text,
        amount: rawAmount,
        unit: _selectedPortion?.name ?? _customUnit,
        calories: double.parse(_caloriesController.text) * scale,
        protein: double.parse(_proteinController.text)  * scale,
        fat:     double.parse(_fatController.text)       * scale,
        carbs:   double.parse(_carbsController.text)     * scale,
        fiber:   double.tryParse(_fiberController.text) != null ? double.parse(_fiberController.text) * scale : null,
        sugar:   double.tryParse(_sugarController.text) != null ? double.parse(_sugarController.text) * scale : null,
        sodium:  double.tryParse(_sodiumController.text) != null ? double.parse(_sodiumController.text) * scale : null,
        saturatedFat: double.tryParse(_saturatedFatController.text) != null ? double.parse(_saturatedFatController.text) * scale : null,
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
      // For named portions, amount is count — convert to grams for micros.
      final amountG = _selectedPortion != null
          ? rawAmount * _selectedPortion!.amountG
          : rawAmount;
      final foodId = entry.foodId;
      final jwt = widget.dbService.jwt;
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
  
  /// Speichere aktuelles Food zur Datenbank
  Future<void> _saveFoodToDatabase() async {
    // Für externe Ergebnisse (OFF, USDA): Nährwerte direkt aus _selectedFood (per 100g),
    // nicht aus den skalierten Controllern.
    final isExternal = _selectedFood != null && _selectedFood!.id.isEmpty;
    final initialCalories = isExternal
        ? _selectedFood!.calories
        : (double.tryParse(_caloriesController.text) ?? 0);
    final initialProtein = isExternal
        ? _selectedFood!.protein
        : (double.tryParse(_proteinController.text) ?? 0);
    final initialFat = isExternal
        ? _selectedFood!.fat
        : (double.tryParse(_fatController.text) ?? 0);
    final initialCarbs = isExternal
        ? _selectedFood!.carbs
        : (double.tryParse(_carbsController.text) ?? 0);

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
      ),
    );
    
    if (result != null) {
      try {
        final service = FoodDatabaseService(widget.dbService);
        final created = await service.createFood(result);
        
        if (mounted) {
          // Directly select the newly created food — user always wants to use it.
          _selectFood(created);
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
  
  /// Bearbeite ein eigenes Food direkt aus den Suchergebnissen
  Future<void> _editFoodInSearch(FoodItem food) async {
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => FoodEditDialog(food: food, dbService: widget.dbService),
    );
    if (result == null) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
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
      final service = FoodDatabaseService(widget.dbService);
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.addFoodScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.storage_outlined),
            tooltip: 'Meine Datenbank',
            onPressed: () async {
              final food = await Navigator.of(context).push<FoodItem>(
                MaterialPageRoute(
                  builder: (context) => FoodDatabaseScreen(
                    dbService: widget.dbService,
                    pickerMode: true,
                  ),
                ),
              );
              if (food != null) {
                _selectFood(food);
              }
            },
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
                            subtitle: Text(
                              '${food.calories.toInt()} kcal / 100${food.servingUnit ?? 'g'}'
                              '${food.brand != null ? ' • ${food.brand}' : ''}'
                              '${food.category != null ? ' • ${food.category}' : ''}'
                              '${food.source != null && !food.source!.contains('Custom') ? ' • ${food.source}' : ''}',
                            ),
                            trailing: (isOFF || food.isPublic)
                                ? const Icon(Icons.chevron_right)
                                : PopupMenuButton<String>(
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
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Bitte Menge eingeben';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return 'Ungültige Menge';
                        }
                        return null;
                      },
                      onChanged: (_) {
                        if (_selectedFood != null) {
                          _calculateNutrition();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPortionSelector(),
                  ),
                ],
              ),
              
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

  const _AddFoodToDatabaseDialog({
    required this.initialName,
    required this.initialCalories,
    required this.initialProtein,
    required this.initialFat,
    required this.initialCarbs,
    this.initialCategory,
    this.initialBrand,
    this.initialPortions = const [],
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
              amountG: double.tryParse(r.amount.text) ?? 0,
            ))
        .where((p) => p.amountG > 0)
        .toList();

    final food = FoodItem(
      id: '',
      userId: null,
      name: _nameController.text,
      calories: double.parse(_caloriesController.text),
      protein: double.parse(_proteinController.text),
      fat: double.parse(_fatController.text),
      carbs: double.parse(_carbsController.text),
      fiber: double.tryParse(_fiberController.text),
      sugar: double.tryParse(_sugarController.text),
      sodium: double.tryParse(_sodiumController.text),
      saturatedFat: double.tryParse(_saturatedFatController.text),
      servingSize: null,
      servingUnit: null,
      portions: portions,
      category: _categoryController.text.isNotEmpty ? _categoryController.text : null,
      brand: _brandController.text.isNotEmpty ? _brandController.text : null,
      barcode: null,
      isPublic: _isPublic,
      isLiquid: _isLiquid,
      isApproved: false,
      source: 'Custom',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    Navigator.of(context).pop(food);
  }
  
  @override
  Widget build(BuildContext context) {
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
