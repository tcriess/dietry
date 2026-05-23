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
import '../services/food_database_service.dart';
import '../services/food_shortcuts_service.dart';
import '../services/barcode_lookup_service.dart';
import '../services/neon_database_service.dart';
import '../l10n/app_localizations.dart';
import 'barcode_scanner_sheet.dart';

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

  /// Startet den Nährwertetikett-Scan (Cloud-Edition, mobil). Null = nicht
  /// verfügbar; dann wird der Etikett-Scan-Button ausgeblendet.
  final VoidCallback? onScanLabel;

  const QuickFoodEntrySheet({
    super.key,
    required this.dbService,
    required this.date,
    required this.initialMealType,
    required this.onAdd,
    required this.onManualEntry,
    this.onOpenTemplates,
    this.onScanLabel,
  });

  @override
  State<QuickFoodEntrySheet> createState() => _QuickFoodEntrySheetState();
}

class _QuickFoodEntrySheetState extends State<QuickFoodEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MealType _mealType;

  /// Raw recent fetch (last 30 days, ordered by created_at desc) before
  /// dedup. Kept raw so the time-of-day re-ranking in [_displayRecent] can
  /// re-evaluate when the user picks a different meal-type chip without
  /// re-hitting the network.
  List<FoodEntry> _rawRecent = [];
  List<FoodItem> _favouriteFoods = [];
  List<FoodShortcut> _shortcuts = [];
  Map<String, FoodItem> _recentFoods = {};
  bool _loading = true;
  String? _addingId;

  /// Name of the most recently logged entry — drives the in-sheet "added"
  /// toast. Null while no toast is showing.
  String? _lastAddedName;
  Timer? _toastTimer;

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

      if (mounted) {
        setState(() {
          _rawRecent = entries;
          _recentFoods = recentFoods;
        });
      }
    } catch (_) {}
  }

  /// Sorts [_rawRecent] by relevance to the current meal context, then
  /// dedupes by lowercase name. Recomputed on every rebuild so changing
  /// the meal-type chip immediately re-ranks the list.
  List<FoodEntry> _displayRecent() =>
      _rankAndDedupRecent(_rawRecent, _mealType, DateTime.now().hour);

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

  Future<void> _addEntry(FoodEntry entry, double? amountG) async {
    if (_addingId != null) return;
    setState(() => _addingId = entry.id);
    try {
      await widget.onAdd(entry);

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
        setState(() => _lastAddedName = entry.name);
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

    // Blocking loader — the lookup hits the local DB and then Open Food Facts,
    // which can take a moment, especially on a cold connection.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    BarcodeLookupResult? result;
    try {
      result = await BarcodeLookupService.lookup(
        barcode,
        dbService: FoodDatabaseService(widget.dbService),
        locale: locale,
      );
    } finally {
      if (mounted) Navigator.of(context).pop(); // dismiss the loader
    }
    if (!mounted) return;

    if (result == null) {
      // A dialog, not a SnackBar: a SnackBar renders at the bottom of the
      // screen, hidden behind this 85%-height bottom sheet.
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final ld = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(ld.barcodeNotFound),
            content: Text(ld.barcodeNotFoundHint),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }
    await _pickFood(result.food);
  }

  // ── Auswahl eines Datenbank-Lebensmittels (Favoriten, Suche, Scan) ───────────

  /// Opens the confirm dialog for a [food] from food_database (per-100g values),
  /// then logs it on confirm.
  Future<void> _pickFood(FoodItem food) async {
    final defaultAmount = food.servingSize ?? 100.0;
    final f = defaultAmount / 100;
    final confirmed = await _confirm(
      name: food.name,
      amount: defaultAmount,
      unit: food.servingUnit ?? 'g',
      calories: food.calories * f,
      protein: food.protein * f,
      fat: food.fat * f,
      carbs: food.carbs * f,
      fiber: food.fiber != null ? food.fiber! * f : null,
      sugar: food.sugar != null ? food.sugar! * f : null,
      sodium: food.sodium != null ? food.sodium! * f : null,
      saturatedFat: food.saturatedFat != null ? food.saturatedFat! * f : null,
      foodId: food.id,
      scaleByAmount: true,
      isLiquid: food.isLiquid,
      amountMl: food.isLiquid ? defaultAmount : null,
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
      foodId: recent.foodId,
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
      foodId: entry.foodId,
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
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // In-sheet "added" toast — visible inside the 85%-tall sheet that
        // would otherwise occlude the ScaffoldMessenger SnackBar.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _lastAddedName == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _AddedToast(name: _lastAddedName!),
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
          child: _query.isEmpty ? _buildBrowse() : _buildSearchResults(),
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
              ),
              _FavouritesTab(
                foods: _favouriteFoods,
                addingId: _addingId,
                onTap: _pickFood,
              ),
              _ShortcutsTab(
                shortcuts: _shortcuts,
                addingId: _addingId,
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
                food.fat, food.carbs),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline, color: Colors.teal),
          onTap: isAdding ? null : () => _pickFood(food),
        );
      },
    );
  }
}

/// Compact one-line macro summary, e.g. "100 g · 250 kcal · P12 F8 K30".
/// [base] is an already-formatted prefix — a serving size or "per 100 g".
String _macroSummary(AppLocalizations l, String base, double kcal,
    double protein, double fat, double carbs) {
  return '$base · ${kcal.toStringAsFixed(0)} kcal · '
      '${l.macroProteinShort}${protein.toStringAsFixed(0)} '
      '${l.macroFatShort}${fat.toStringAsFixed(0)} '
      '${l.macroCarbsShort}${carbs.toStringAsFixed(0)}';
}

// ── Recent ranking ────────────────────────────────────────────────────────────

/// Circular hour distance, 0–12. e.g. distance(23, 1) == 2.
int _hourDistance(int a, int b) {
  final d = (a - b).abs();
  return d > 12 ? 24 - d : d;
}

/// Lower is better: (0=meal-type match, 1=other), then hour-of-day distance,
/// then negative recency. Keeps "breakfast banana" at the top in the morning
/// even if the most recently logged banana was at dinner last night.
int _compareRecent(FoodEntry a, FoodEntry b, MealType mealType, int hour) {
  final aMatch = a.mealType == mealType ? 0 : 1;
  final bMatch = b.mealType == mealType ? 0 : 1;
  if (aMatch != bMatch) return aMatch - bMatch;

  final aHourDist = _hourDistance(a.createdAt.hour, hour);
  final bHourDist = _hourDistance(b.createdAt.hour, hour);
  if (aHourDist != bHourDist) return aHourDist - bHourDist;

  return b.createdAt.compareTo(a.createdAt);
}

/// Sorts [entries] by relevance to the current ([mealType], [hour]) context,
/// then dedupes by lowercase name, keeping the best-ranked entry per name.
List<FoodEntry> _rankAndDedupRecent(
    List<FoodEntry> entries, MealType mealType, int hour) {
  final sorted = entries.toList()
    ..sort((a, b) => _compareRecent(a, b, mealType, hour));
  final seen = <String>{};
  final result = <FoodEntry>[];
  for (final e in sorted) {
    if (seen.add(e.name.toLowerCase().trim()) && result.length < 30) {
      result.add(e);
    }
  }
  return result;
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

  const _RecentTab({
    required this.entries,
    required this.addingId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (entries.isEmpty) {
      return Center(
        child: Text(l.noRecentEntries,
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: [
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
                      e.fat, e.carbs),
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
                food.fat, food.carbs),
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
                  sc.calories, sc.protein, sc.fat, sc.carbs),
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
      foodId: widget.foodId,
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
          label: Text(l.shortcut),
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
