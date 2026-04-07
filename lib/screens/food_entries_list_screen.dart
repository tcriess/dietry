import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../app_features.dart';
import '../models/food_entry.dart';
import '../services/neon_database_service.dart';
import '../services/data_store.dart';
import '../services/sync_service.dart';
import '../services/food_database_service.dart';
import '../services/food_search_service.dart';
import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../widgets/quick_food_entry_sheet.dart';
import 'add_food_entry_screen.dart';
import 'edit_food_entry_screen.dart';
import 'food_database_screen.dart';

/// Screen zur Anzeige und Verwaltung aller Food-Entries eines Tages
class FoodEntriesListScreen extends StatefulWidget {
  final NeonDatabaseService dbService;
  final DateTime selectedDay;
  final void Function(int offset) onChangeDay;
  final VoidCallback onJumpToToday;

  const FoodEntriesListScreen({
    super.key,
    required this.dbService,
    required this.selectedDay,
    required this.onChangeDay,
    required this.onJumpToToday,
  });
  
  @override
  State<FoodEntriesListScreen> createState() => _FoodEntriesListScreenState();
}

class _FoodEntriesListScreenState extends State<FoodEntriesListScreen> {
  final _store = DataStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _deleteEntry(FoodEntry entry) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final ld = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(ld.deleteEntryTitle),
          content: Text(ld.deleteEntryConfirm(entry.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(ld.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(ld.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Optimistic remove — UI updates immediately.
    _store.removeFoodEntry(entry.id);

    await SyncService.instance.deleteFoodEntry(entry.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.entryDeleted),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Determines the most likely meal type based on the current time of day.
  MealType _suggestMealType() {
    final hour = DateTime.now().hour;
    if (hour < 10) return MealType.breakfast;
    if (hour < 14) return MealType.lunch;
    if (hour < 18) return MealType.snack;
    return MealType.dinner;
  }

  Future<void> _showQuickAddSheet() async {
    final db = widget.dbService;
    final jwt = db.jwt;
    final userId = db.userId;
    if (jwt == null || userId == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: QuickFoodEntrySheet(
          dbService: db,
          date: widget.selectedDay,
          initialMealType: _suggestMealType(),
          onAdd: (entry) async {
            final saved = await SyncService.instance.createFoodEntry(entry);
            if (saved != null) DataStore.instance.addFoodEntry(saved);
            if (AppFeatures.microNutrients && entry.foodId != null) {
              premiumFeatures.copyFoodMicrosToEntry(
                foodId: entry.foodId!,
                entryId: saved?.id ?? entry.id,
                userId: userId,
                amountG: entry.amount,
                authToken: jwt,
                apiUrl: NeonDatabaseService.dataApiUrl,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _showMealTemplatesSheet() async {
    appLogger.d('🍽️ _showMealTemplatesSheet called');
    final db = widget.dbService;
    final jwt = db.jwt;
    final userId = db.userId;
    appLogger.d('🍽️ jwt=${jwt != null}, userId=$userId, premium=${premiumFeatures.runtimeType}');
    if (jwt == null || userId == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.7,
        child: premiumFeatures.buildMealTemplatesSheet(
        userId: userId,
        date: widget.selectedDay,
        authToken: jwt,
        dataApiUrl: NeonDatabaseService.dataApiUrl,
        onSearchIngredient: (query, {searchOnline = false}) async {
          if (searchOnline) {
            final results = await FoodSearchService().search(query, limit: 20);
            return results.map((r) => MealIngredientCandidate(
              id: r.food.id.isNotEmpty ? r.food.id : null,
              name: r.food.name,
              calories: r.food.calories,
              protein: r.food.protein,
              fat: r.food.fat,
              carbs: r.food.carbs,
              fiber: r.food.fiber,
              sugar: r.food.sugar,
              sodium: r.food.sodium,
              source: r.food.source,
              portions: r.food.portions
                  .map((p) => (name: p.name, weightG: p.amountG))
                  .toList(),
              isLiquid: r.food.isLiquid,
            )).toList();
          } else {
            final items = await FoodDatabaseService(widget.dbService)
                .searchFoods(query, limit: 20);
            return items.map((f) => MealIngredientCandidate(
              id: f.id.isNotEmpty ? f.id : null,
              name: f.name,
              calories: f.calories,
              protein: f.protein,
              fat: f.fat,
              carbs: f.carbs,
              fiber: f.fiber,
              sugar: f.sugar,
              sodium: f.sodium,
              portions: f.portions
                  .map((p) => (name: p.name, weightG: p.amountG))
                  .toList(),
              isLiquid: f.isLiquid,
            )).toList();
          }
        },
        onLog: (data) async {
          final entry = FoodEntry(
            id: const Uuid().v4(),
            userId: userId,
            entryDate: widget.selectedDay,
            mealType: MealType.fromJson(data.mealType),
            name: data.name,
            amount: data.amount,
            unit: data.unit,
            calories: data.calories,
            protein: data.protein,
            fat: data.fat,
            carbs: data.carbs,
            fiber: data.fiber,
            sugar: data.sugar,
            sodium: data.sodium,
            // Meals are never marked as isLiquid (they can be mixed)
            // But amountMl is set if there are liquid ingredients
            isLiquid: false,
            amountMl: data.liquidMlContribution,
            isMeal: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          final saved = await SyncService.instance.createFoodEntry(entry);
          if (saved != null) {
            DataStore.instance.addFoodEntry(saved);
          }
        },
        ),
      ),
    );
  }

  Future<void> _editEntry(FoodEntry entry) async {
    // EditFoodEntryScreen updates DataStore directly on save.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditFoodEntryScreen(
          dbService: widget.dbService,
          entry: entry,
        ),
      ),
    );
  }
  
  /// Formatiert Menge + Einheit für die Anzeige.
  /// g/ml: "150g", "250ml" — benannte Portion: "1 Scheibe (30g)"
  String _formatEntryAmount(FoodEntry entry) {
    final unit = entry.unit;
    if (unit == 'g' || unit == 'ml') {
      return '${entry.amount.toStringAsFixed(0)}$unit';
    }
    // Meal template entries: amount is portion count.
    if (unit == 'Portion') {
      final count = entry.amount;
      final countStr = count == count.truncateToDouble()
          ? count.toInt().toString()
          : count.toStringAsFixed(1);
      return count == 1.0 ? '1 Portion' : '$countStr Portionen';
    }
    // Named food portion: amount is portion count.
    final count = entry.amount;
    final countStr = count == count.truncateToDouble()
        ? count.toInt().toString()
        : count.toStringAsFixed(1);
    return '$countStr × $unit';
  }

  /// Farbe für Meal-Type Avatar
  Color _getMealTypeColor(MealType mealType) {
    switch (mealType) {
      case MealType.breakfast:
        return Colors.orange.shade100;
      case MealType.lunch:
        return Colors.blue.shade100;
      case MealType.dinner:
        return Colors.purple.shade100;
      case MealType.snack:
        return Colors.green.shade100;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formattedDate = DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.selectedDay);
    final isToday = DateUtils.isSameDay(widget.selectedDay, DateTime.now());
    final entries = _store.foodEntries;

    return Scaffold(
      body: Column(
        children: [
          // Tagesauswahl
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: l.previousDay,
                  onPressed: () => widget.onChangeDay(-1),
                ),
                Column(
                  children: [
                    Text(
                      l.entriesTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      formattedDate,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: widget.onJumpToToday,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l.today,
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: l.nextDay,
                  onPressed: () => widget.onChangeDay(1),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Entry-Liste
          Expanded(
            child: _store.isLoading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.no_food, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              l.entriesEmpty,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.entriesEmptyHint,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          // Gruppiere nach Meal-Type
                          ...MealType.values.map((mealType) {
                            final mealEntries = entries.where((e) => e.mealType == mealType).toList();
                            if (mealEntries.isEmpty) return const SizedBox.shrink();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Meal-Type Header
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  child: Row(
                                    children: [
                                      Text(mealType.icon, style: const TextStyle(fontSize: 24)),
                                      const SizedBox(width: 8),
                                      Text(
                                        mealType.localizedName(l),
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      // Summe für diese Mahlzeit (only show if not macro-only mode)
                                      if (_store.goal?.macroOnly != true)
                                        Text(
                                          '${mealEntries.fold(0.0, (sum, e) => sum + e.calories).toStringAsFixed(0)} kcal',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // Entries für diese Mahlzeit
                                ...mealEntries.map((entry) => Dismissible(
                                  key: Key(entry.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    color: Colors.red,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (context) {
                                        final ld = AppLocalizations.of(context)!;
                                        return AlertDialog(
                                          title: Text(ld.deleteEntryTitle),
                                          content: Text(ld.deleteEntryConfirm(entry.name)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(false),
                                              child: Text(ld.cancel),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(true),
                                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                                              child: Text(ld.delete),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  onDismissed: (direction) {
                                    _deleteEntry(entry);
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getMealTypeColor(mealType),
                                        child: Text(
                                          mealType.icon,
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                      ),
                                      title: Text(entry.name),
                                      subtitle: Text(
                                        _store.goal?.macroOnly == true
                                            ? _formatEntryAmount(entry)
                                            : '${_formatEntryAmount(entry)} • ${entry.calories.toStringAsFixed(0)} kcal',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Makros
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'P: ${entry.protein.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                              Text(
                                                'F: ${entry.fat.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                              Text(
                                                'C: ${entry.carbs.toStringAsFixed(0)}g',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 4),
                                          // Mikronährstoffe (Premium)
                                          if (AppFeatures.microNutrients)
                                            IconButton(
                                              icon: const Icon(Icons.science_outlined, size: 20),
                                              onPressed: () {
                                                final db = widget.dbService;
                                                final jwt = db.jwt;
                                                final userId = db.userId;
                                                if (jwt == null || userId == null) return;
                                                premiumFeatures.showMicroNutrientsSheet(
                                                  context: context,
                                                  entryId: entry.id,
                                                  entryName: entry.name,
                                                  userId: userId,
                                                  authToken: jwt,
                                                  apiUrl: NeonDatabaseService.dataApiUrl,
                                                );
                                              },
                                              tooltip: 'Mikronährstoffe',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32,
                                              ),
                                            ),
                                          // Löschen-Button
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 20),
                                            color: Colors.red.shade400,
                                            onPressed: () => _deleteEntry(entry),
                                            tooltip: l.delete,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _editEntry(entry),
                                    ),
                                  ),
                                )),
                                
                                const SizedBox(height: 8),
                              ],
                            );
                          }),
                        ],
                      ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'fab_quick_add',
            onPressed: _showQuickAddSheet,
            tooltip: 'Schnelleintrag',
            child: const Icon(Icons.bolt),
          ),
          const SizedBox(width: 12),
          if (AppFeatures.mealTemplates) ...[
            FloatingActionButton(
              heroTag: 'fab_meal_templates',
              onPressed: _showMealTemplatesSheet,
              tooltip: 'Mahlzeiten-Vorlagen',
              child: const Icon(Icons.restaurant_menu),
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton(
            heroTag: 'fab_database',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      FoodDatabaseScreen(dbService: widget.dbService),
                ),
              );
            },
            tooltip: l.myFoods,
            child: const Icon(Icons.storage_outlined),
          ),
          const SizedBox(width: 12),
          if (MediaQuery.of(context).size.width >= 550)
            FloatingActionButton.extended(
              heroTag: 'fab_add',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AddFoodEntryScreen(
                      dbService: widget.dbService,
                      selectedDate: widget.selectedDay,
                    ),
                  ),
                );
                // DataStore is updated directly by AddFoodEntryScreen.
              },
              icon: const Icon(Icons.add),
              label: Text(l.addEntry),
            )
          else
            FloatingActionButton(
              heroTag: 'fab_add',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AddFoodEntryScreen(
                      dbService: widget.dbService,
                      selectedDate: widget.selectedDay,
                    ),
                  ),
                );
                // DataStore is updated directly by AddFoodEntryScreen.
              },
              tooltip: l.addEntry,
              child: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }
}

