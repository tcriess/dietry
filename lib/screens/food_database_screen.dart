import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dietry_cloud/dietry_cloud.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
import '../services/food_database_service.dart';
import '../services/neon_database_service.dart';
import '../app_features.dart';
import '../l10n/app_localizations.dart';

/// Screen zur Verwaltung eigener Lebensmittel in der Datenbank.
///
/// Listet alle privaten (eigenen) Einträge mit Edit/Delete.
/// Tippen auf einen Eintrag gibt ihn als Pop-Ergebnis zurück
/// (für Auswahl in AddFoodEntryScreen).
class FoodDatabaseScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const FoodDatabaseScreen({super.key, required this.dbService});

  @override
  State<FoodDatabaseScreen> createState() => _FoodDatabaseScreenState();
}

class _FoodDatabaseScreenState extends State<FoodDatabaseScreen> {
  List<FoodItem> _foods = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    setState(() => _isLoading = true);
    try {
      final service = FoodDatabaseService(widget.dbService);
      final foods = await service.getMyFoods();
      if (mounted) setState(() => _foods = foods);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editFood(FoodItem food) async {
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => FoodEditDialog(food: food),
    );
    if (result == null) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
      await service.updateFood(result);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.foodUpdated(result.name)),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadFoods();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleFavourite(FoodItem food) async {
    final newValue = !food.isFavourite;
    // Optimistic update
    setState(() {
      final idx = _foods.indexWhere((f) => f.id == food.id);
      if (idx != -1) _foods[idx] = food.copyWith(isFavourite: newValue);
    });
    try {
      await FoodDatabaseService(widget.dbService)
          .toggleFoodFavourite(food.id, isFavourite: newValue);
    } catch (e) {
      // Revert on error
      setState(() {
        final idx = _foods.indexWhere((f) => f.id == food.id);
        if (idx != -1) _foods[idx] = food;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteFood(FoodItem food) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l.deleteFoodTitle),
          content: Text(l.deleteFoodConfirm(food.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
      await service.deleteFood(food.id);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.foodDeleted), backgroundColor: Colors.green),
        );
      }
      _loadFoods();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addFood() async {
    final result = await showDialog<FoodItem>(
      context: context,
      builder: (context) => const FoodEditDialog(food: null),
    );
    if (result == null) return;

    try {
      final service = FoodDatabaseService(widget.dbService);
      final created = await service.createFood(result);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.foodAdded(created.name)),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadFoods();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.foodDatabaseTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFoods,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addFood,
        tooltip: l.add,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _foods.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.no_food, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        l.entriesEmpty,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.entriesEmptyHint,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _foods.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final food = _foods[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          food.name[0].toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(food.name)),
                          if (food.isPublic)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: food.isApproved
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    food.isApproved ? Icons.public : Icons.pending_outlined,
                                    size: 12,
                                    color: food.isApproved
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    food.isApproved ? l.statusPublic : l.statusPending,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: food.isApproved
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${food.calories.toInt()} kcal · '
                        'P ${food.protein.toStringAsFixed(0)}g · '
                        'F ${food.fat.toStringAsFixed(0)}g · '
                        'KH ${food.carbs.toStringAsFixed(0)}g'
                        '${food.category != null ? ' · ${food.category}' : ''}',
                      ),
                      onTap: () => Navigator.of(context).pop(food),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              food.isFavourite ? Icons.star : Icons.star_border,
                              size: 20,
                              color: food.isFavourite
                                  ? Colors.amber.shade600
                                  : Colors.grey.shade400,
                            ),
                            tooltip: food.isFavourite
                                ? 'Aus Favoriten entfernen'
                                : 'Als Favorit markieren',
                            onPressed: () => _toggleFavourite(food),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          if (AppFeatures.microNutrients)
                            IconButton(
                              icon: const Icon(Icons.science_outlined, size: 20),
                              tooltip: 'Mikronährstoffe',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () {
                                final jwt = widget.dbService.jwt;
                                final userId = widget.dbService.userId;
                                if (jwt == null || userId == null) return;
                                premiumFeatures.showFoodDatabaseMicrosSheet(
                                  context: context,
                                  foodId: food.id,
                                  foodName: food.name,
                                  userId: userId,
                                  authToken: jwt,
                                  apiUrl: NeonDatabaseService.dataApiUrl,
                                );
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: l.edit,
                            onPressed: () => _editFood(food),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            tooltip: l.delete,
                            onPressed: () => _deleteFood(food),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// Dialog zum Erstellen oder Bearbeiten eines Lebensmittels.
/// [food] == null → neues Lebensmittel anlegen.
class FoodEditDialog extends StatefulWidget {
  final FoodItem? food;

  const FoodEditDialog({super.key, required this.food});

  @override
  State<FoodEditDialog> createState() => FoodEditDialogState();
}

class FoodEditDialogState extends State<FoodEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _categoryController;
  late final TextEditingController _brandController;
  late final TextEditingController _fiberController;
  late final TextEditingController _sugarController;
  late final TextEditingController _sodiumController;
  late final TextEditingController _saturatedFatController;
  final List<({TextEditingController name, TextEditingController amount})> _portionRows = [];
  late bool _isPublic;
  late bool _isLiquid;

  bool get _isEdit => widget.food != null;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _nameController = TextEditingController(text: f?.name ?? '');
    _caloriesController = TextEditingController(
        text: f != null ? f.calories.toStringAsFixed(0) : '');
    _proteinController = TextEditingController(
        text: f != null ? f.protein.toStringAsFixed(1) : '');
    _fatController =
        TextEditingController(text: f != null ? f.fat.toStringAsFixed(1) : '');
    _carbsController = TextEditingController(
        text: f != null ? f.carbs.toStringAsFixed(1) : '');
    _categoryController = TextEditingController(text: f?.category ?? '');
    _brandController = TextEditingController(text: f?.brand ?? '');
    _fiberController = TextEditingController(
        text: f?.fiber != null ? f!.fiber!.toStringAsFixed(1) : '');
    _sugarController = TextEditingController(
        text: f?.sugar != null ? f!.sugar!.toStringAsFixed(1) : '');
    _sodiumController = TextEditingController(
        text: f?.sodium != null ? f!.sodium!.toStringAsFixed(1) : '');
    _saturatedFatController = TextEditingController(
        text: f?.saturatedFat != null ? f!.saturatedFat!.toStringAsFixed(1) : '');
    for (final p in (widget.food?.portions ?? [])) {
      _portionRows.add((
        name: TextEditingController(text: p.name),
        amount: TextEditingController(
            text: p.amountG % 1 == 0 ? p.amountG.toInt().toString() : p.amountG.toString()),
      ));
    }
    _isPublic = f?.isPublic ?? false;
    _isLiquid = f?.isLiquid ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _saturatedFatController.dispose();
    for (final row in _portionRows) {
      row.name.dispose();
      row.amount.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final food = FoodItem(
      id: widget.food?.id ?? '',
      userId: widget.food?.userId,
      name: _nameController.text.trim(),
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
      portions: _portionRows
          .where((r) => r.name.text.trim().isNotEmpty && r.amount.text.isNotEmpty)
          .map((r) => FoodPortion(
                name: r.name.text.trim(),
                amountG: double.tryParse(r.amount.text) ?? 0,
              ))
          .where((p) => p.amountG > 0)
          .toList(),
      category:
          _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null,
      brand: _brandController.text.trim().isNotEmpty ? _brandController.text.trim() : null,
      barcode: widget.food?.barcode,
      isPublic: _isPublic,
      isApproved: false,  // Immer zurücksetzen – Admin muss erneut freigeben
      isLiquid: _isLiquid,
      source: widget.food?.source ?? 'Custom',
      createdAt: widget.food?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.of(context).pop(food);
  }

  Widget _numField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required String requiredMsg,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      validator: (v) =>
          (v == null || v.isEmpty) ? requiredMsg : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(_isEdit ? l.editEntryTitle : l.newFood),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isEdit && widget.food!.isApproved) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dieser Eintrag ist öffentlich freigegeben. '
                            'Nach dem Speichern muss er erneut von einem Admin bestätigt werden.',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Nährwerte pro 100 g bzw. 100 ml angeben',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l.foodName,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l.requiredField : null,
                ),
                const SizedBox(height: 10),

                // Kalorien & Protein
                Row(
                  children: [
                    Expanded(
                        child: _numField(
                            controller: _caloriesController,
                            label: l.foodCaloriesPer100,
                            suffix: 'kcal',
                            requiredMsg: l.requiredField)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _numField(
                            controller: _proteinController,
                            label: l.foodProteinPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                  ],
                ),
                const SizedBox(height: 10),

                // Fett & KH
                Row(
                  children: [
                    Expanded(
                        child: _numField(
                            controller: _fatController,
                            label: l.foodFatPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _numField(
                            controller: _carbsController,
                            label: l.foodCarbsPer100,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                  ],
                ),
                const SizedBox(height: 10),

                // Optional: Fiber & Saturated Fat
                Row(
                  children: [
                    Expanded(
                        child: _numField(
                            controller: _fiberController,
                            label: l.nutrientFiber,
                            suffix: 'g',
                            requiredMsg: l.requiredField)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                          controller: _saturatedFatController,
                          decoration: InputDecoration(
                            labelText: l.nutrientSaturatedFat,
                            suffixText: 'g',
                            helperText: l.ofWhichFat,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                  ],
                ),
                const SizedBox(height: 10),

                // Optional: Sugar & Salt
                Row(
                  children: [
                    Expanded(
                        child: TextFormField(
                          controller: _sugarController,
                          decoration: InputDecoration(
                            labelText: l.nutrientSugar,
                            suffixText: 'g',
                            helperText: l.ofWhichCarbs,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                    const SizedBox(width: 8),
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
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        )),
                  ],
                ),
                const SizedBox(height: 10),

                // Kategorie
                TextFormField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: l.foodCategory,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),

                // Marke
                TextFormField(
                  controller: _brandController,
                  decoration: InputDecoration(
                    labelText: l.foodBrand,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                // Portionsgrößen
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l.foodPortionsTitle,
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
                      label: Text(l.add),
                    ),
                  ],
                ),
                if (_portionRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l.foodPortionsEmpty,
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
                const SizedBox(height: 4),

                // Öffentlich / Privat
                SwitchListTile(
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                  title: Text(l.foodPublic),
                  subtitle: Text(
                    _isPublic ? l.foodPublicOn : l.foodPublicOff,
                  ),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _isPublic ? Icons.public : Icons.lock_outline,
                    color: _isPublic ? Colors.green : Colors.grey,
                  ),
                ),

                // Flüssigkeit
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
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, foregroundColor: Colors.white),
          child: Text(_isEdit ? l.save : l.add),
        ),
      ],
    );
  }
}
