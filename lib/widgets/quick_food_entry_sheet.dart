import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/food_entry.dart';
import '../models/food_item.dart';
import '../models/food_shortcut.dart';
import '../services/food_database_service.dart';
import '../services/food_shortcuts_service.dart';
import '../services/neon_database_service.dart';
import '../l10n/app_localizations.dart';

/// Bottom-Sheet für schnellen Mahlzeiten-Eintrag.
///
/// Drei Tabs:
///   • Zuletzt    – kürzlich eingetragene Lebensmittel (letzte 30 Tage, dedup.)
///   • Favoriten  – Lebensmittel mit is_favourite=true aus food_database
///   • Kurzbefehle– nutzerkonfigurierte Einzel-Einträge (SharedPreferences)
///
/// Jeder Eintrag kann mit einem Tipp direkt hinzugefügt oder per Langtipp
/// als Kurzbefehl gespeichert werden.
class QuickFoodEntrySheet extends StatefulWidget {
  final NeonDatabaseService dbService;
  final DateTime date;
  final MealType initialMealType;

  /// Callback: erhält einen vollständig gefüllten [FoodEntry] (inkl. UUID).
  /// Der Aufrufer ist für Persistenz + DataStore-Update zuständig.
  final Future<void> Function(FoodEntry) onAdd;

  const QuickFoodEntrySheet({
    super.key,
    required this.dbService,
    required this.date,
    required this.initialMealType,
    required this.onAdd,
  });

  @override
  State<QuickFoodEntrySheet> createState() => _QuickFoodEntrySheetState();
}

class _QuickFoodEntrySheetState extends State<QuickFoodEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MealType _mealType;

  List<FoodEntry> _recentEntries = [];
  List<FoodItem> _favouriteFoods = [];
  List<FoodShortcut> _shortcuts = [];
  bool _loading = true;
  String? _addingId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mealType = widget.initialMealType;
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    final start = end.subtract(const Duration(days: 30));
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
          .limit(200);

      final entries = (response as List)
          .map((json) => FoodEntry.fromJson(json as Map<String, dynamic>))
          .toList();

      // Dedup by lowercase name, keep most recent
      final seen = <String>{};
      final deduped = <FoodEntry>[];
      for (final e in entries) {
        if (seen.add(e.name.toLowerCase().trim()) && deduped.length < 30) {
          deduped.add(e);
        }
      }
      if (mounted) setState(() => _recentEntries = deduped);
    } catch (_) {}
  }

  Future<void> _loadFavourites() async {
    try {
      final foods =
          await FoodDatabaseService(widget.dbService).getFavouriteFoods();
      if (mounted) setState(() => _favouriteFoods = foods);
    } catch (_) {}
  }

  Future<void> _loadShortcuts() async {
    final list = await FoodShortcutsService.loadShortcuts();
    if (mounted) setState(() => _shortcuts = list);
  }

  // ── add helpers ──────────────────────────────────────────────────────────────

  Future<void> _addEntry(FoodEntry entry) async {
    if (_addingId != null) return;
    setState(() => _addingId = entry.id);
    try {
      await widget.onAdd(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${entry.name} hinzugefügt'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ));
      }
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  FoodEntry _entryFromShortcut(FoodShortcut sc) {
    final userId = widget.dbService.userId!;
    return FoodEntry(
      id: const Uuid().v4(),
      userId: userId,
      foodId: sc.foodId,
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
      isLiquid: sc.isLiquid,
      amountMl: sc.amountMl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // ── confirm dialog ────────────────────────────────────────────────────────────

  /// Returns a confirmed FoodEntry (amount may have been edited), or null if cancelled.
  Future<FoodEntry?> _confirm({
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
    String? foodId,
    bool scaleByAmount = false, // true for food_database items (per-100g values)
    FoodItem? food,
    FoodEntry? recentEntry,
    bool isLiquid = false,
    double? amountMl,
  }) {
    return showDialog<FoodEntry>(
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
        foodId: foodId,
        scaleByAmount: scaleByAmount,
        food: food,
        recentEntry: recentEntry,
        isLiquid: isLiquid,
        amountMl: amountMl,
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
    bool isLiquid = false,
    double? amountMl,
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
      isLiquid: isLiquid,
      amountMl: amountMl,
    );
    await FoodShortcutsService.addShortcut(sc);
    await _loadShortcuts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kurzbefehl "$label" gespeichert'),
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
              const Icon(Icons.bolt, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Schnelleintrag',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                          if (v) setState(() => _mealType = mt);
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Tabs
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Zuletzt'),
            Tab(text: 'Favoriten'),
            Tab(text: 'Kurzbefehle'),
          ],
        ),
        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _RecentTab(
                      entries: _recentEntries,
                      addingId: _addingId,
                      onTap: (entry) async {
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
                          foodId: entry.foodId,
                          isLiquid: entry.isLiquid,
                          amountMl: entry.amountMl,
                          recentEntry: entry,
                        );
                        if (confirmed != null) await _addEntry(confirmed);
                      },
                    ),
                    _FavouritesTab(
                      foods: _favouriteFoods,
                      addingId: _addingId,
                      onTap: (food) async {
                        final defaultAmount = food.servingSize ?? 100.0;
                        final amountMlValue = food.isLiquid ? defaultAmount : null;
                        final confirmed = await _confirm(
                          name: food.name,
                          amount: defaultAmount,
                          unit: food.servingUnit ?? 'g',
                          calories: food.calories * defaultAmount / 100,
                          protein: food.protein * defaultAmount / 100,
                          fat: food.fat * defaultAmount / 100,
                          carbs: food.carbs * defaultAmount / 100,
                          fiber: food.fiber != null
                              ? food.fiber! * defaultAmount / 100
                              : null,
                          sugar: food.sugar != null
                              ? food.sugar! * defaultAmount / 100
                              : null,
                          sodium: food.sodium != null
                              ? food.sodium! * defaultAmount / 100
                              : null,
                          foodId: food.id,
                          scaleByAmount: true,
                          isLiquid: food.isLiquid,
                          amountMl: amountMlValue,
                          food: food,
                        );
                        if (confirmed != null) await _addEntry(confirmed);
                      },
                    ),
                    _ShortcutsTab(
                      shortcuts: _shortcuts,
                      addingId: _addingId,
                      onTap: (sc) async {
                        final entry = _entryFromShortcut(sc);
                        await _addEntry(entry);
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
}

// ── Recent tab ────────────────────────────────────────────────────────────────

class _RecentTab extends StatelessWidget {
  final List<FoodEntry> entries;
  final String? addingId;
  final void Function(FoodEntry) onTap;

  const _RecentTab({
    required this.entries,
    required this.addingId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('Noch keine Einträge vorhanden.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        final isAdding = addingId == e.id;
        final _eCount = e.amount;
        final _eCountStr = _eCount == _eCount.truncateToDouble()
            ? _eCount.toInt().toString()
            : _eCount.toStringAsFixed(1);
        final amountStr = e.unit == 'g' || e.unit == 'ml'
            ? '${e.amount.toStringAsFixed(0)}${e.unit}'
            : e.unit == 'Portion'
                ? '$_eCountStr Portion${_eCount != 1.0 ? 'en' : ''}'
                : '$_eCountStr × ${e.unit}';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.orange.shade50,
            child:
                const Icon(Icons.history, color: Colors.orange, size: 20),
          ),
          title: Text(e.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            '$amountStr · ${e.calories.toStringAsFixed(0)} kcal  '
            'P${e.protein.toStringAsFixed(0)} F${e.fat.toStringAsFixed(0)} K${e.carbs.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline, color: Colors.teal),
          onTap: isAdding ? null : () => onTap(e),
        );
      },
    );
  }
}

// ── Favourites tab ────────────────────────────────────────────────────────────

class _FavouritesTab extends StatelessWidget {
  final List<FoodItem> foods;
  final String? addingId;
  final void Function(FoodItem) onTap;

  const _FavouritesTab({
    required this.foods,
    required this.addingId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Favoriten.\n'
            'Markiere Lebensmittel in der Lebensmittel-Datenbank '
            'mit dem Stern-Symbol.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
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
            'pro 100g · ${food.calories.toStringAsFixed(0)} kcal  '
            'P${food.protein.toStringAsFixed(0)} F${food.fat.toStringAsFixed(0)} K${food.carbs.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline, color: Colors.teal),
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

  const _ShortcutsTab({
    required this.shortcuts,
    required this.addingId,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (shortcuts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Kurzbefehle.\n'
            'Tippe auf einen Eintrag unter „Zuletzt" oder „Favoriten" '
            'und wähle „Als Kurzbefehl speichern".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
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
              '${sc.amount.toStringAsFixed(0)} ${sc.unit} · '
              '${sc.calories.toStringAsFixed(0)} kcal  '
              'P${sc.protein.toStringAsFixed(0)} F${sc.fat.toStringAsFixed(0)} K${sc.carbs.toStringAsFixed(0)}',
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
    bool isLiquid,
    double? amountMl,
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
    this.foodId,
    required this.scaleByAmount,
    this.food,
    this.recentEntry,
    required this.isLiquid,
    this.amountMl,
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
  bool _savingShortcut = false;

  double get _currentAmount =>
      double.tryParse(_amountCtrl.text) ?? widget.initialAmount;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.initialAmount.toStringAsFixed(0));
    _mealType = widget.mealType;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  FoodEntry _buildEntry() {
    final amount = _currentAmount;
    final scale = amount / widget.initialAmount;
    final f = widget.scaleByAmount ? amount / 100.0 : scale;
    final food = widget.food;
    final re = widget.recentEntry;

    double calories, protein, fat, carbs;
    double? fiber, sugar, sodium, scaledAmountMl;

    if (food != null) {
      calories = food.calories * f;
      protein = food.protein * f;
      fat = food.fat * f;
      carbs = food.carbs * f;
      fiber = food.fiber != null ? food.fiber! * f : null;
      sugar = food.sugar != null ? food.sugar! * f : null;
      sodium = food.sodium != null ? food.sodium! * f : null;
    } else if (re != null) {
      calories = re.calories * scale;
      protein = re.protein * scale;
      fat = re.fat * scale;
      carbs = re.carbs * scale;
      fiber = re.fiber != null ? re.fiber! * scale : null;
      sugar = re.sugar != null ? re.sugar! * scale : null;
      sodium = re.sodium != null ? re.sodium! * scale : null;
    } else {
      calories = widget.calories * scale;
      protein = widget.protein * scale;
      fat = widget.fat * scale;
      carbs = widget.carbs * scale;
      fiber = widget.fiber != null ? widget.fiber! * scale : null;
      sugar = widget.sugar != null ? widget.sugar! * scale : null;
      sodium = widget.sodium != null ? widget.sodium! * scale : null;
    }

    // Scale amountMl if present
    if (widget.isLiquid && widget.amountMl != null) {
      scaledAmountMl = widget.amountMl! * scale;
    }

    return FoodEntry(
      id: const Uuid().v4(),
      userId: widget.userId,
      foodId: widget.foodId,
      entryDate: widget.date,
      mealType: _mealType,
      name: widget.name,
      amount: amount,
      unit: widget.unit,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      isLiquid: widget.isLiquid,
      amountMl: scaledAmountMl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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
          // Amount
          TextFormField(
            controller: _amountCtrl,
            decoration: InputDecoration(
              labelText: 'Menge',
              suffixText: widget.unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Nutrition preview
          _NutritionPreview(entry: _buildEntry()),
          const SizedBox(height: 12),
          // Meal type
          Wrap(
            spacing: 6,
            children: MealType.values
                .map((mt) => ChoiceChip(
                      label: Text('${mt.icon} ${mt.localizedName(l)}',
                          style: const TextStyle(fontSize: 11)),
                      selected: _mealType == mt,
                      onSelected: (v) {
                        if (v) {
                          setState(() => _mealType = mt);
                          widget.onMealTypeChanged(mt);
                        }
                      },
                    ))
                .toList(),
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
          label: const Text('Kurzbefehl'),
          onPressed: _savingShortcut
              ? null
              : () async {
                  setState(() => _savingShortcut = true);
                  final entry = _buildEntry();
                  await widget.onSaveAsShortcut(
                    label: widget.name,
                    foodId: widget.foodId,
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
                    isLiquid: entry.isLiquid,
                    amountMl: entry.amountMl,
                  );
                  setState(() => _savingShortcut = false);
                },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_buildEntry()),
          child: const Text('Hinzufügen'),
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
          _MacroChip(label: 'P',
              value: '${entry.protein.toStringAsFixed(1)}g'),
          _MacroChip(label: 'F',
              value: '${entry.fat.toStringAsFixed(1)}g'),
          _MacroChip(label: 'KH',
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
