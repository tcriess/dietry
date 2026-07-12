import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/gear.dart';
import '../models/physical_activity.dart';
import '../services/app_logger.dart';
import '../services/sync_service.dart';
import '../utils/number_utils.dart';

/// Manage gear (running shoes, bikes, …) and see what each one has clocked up.
///
/// Distance and time come from the activities the gear is attached to, so this
/// screen is read-mostly: the interesting number is "412 of 800 km", which is
/// what tells a runner when to replace a pair of shoes.
class GearScreen extends StatefulWidget {
  const GearScreen({super.key});

  @override
  State<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends State<GearScreen> {
  List<Gear> _gear = [];
  Map<String, GearTotals> _totals = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sync = SyncService.instance;
    final gear = await sync.getGear();
    final totals = await sync.getGearTotals();
    if (!mounted) return;
    setState(() {
      _gear = gear;
      _totals = totals;
      _isLoading = false;
    });
  }

  Future<void> _edit({Gear? gear}) async {
    final result = await showDialog<Gear>(
      context: context,
      builder: (_) => _GearEditDialog(gear: gear),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    try {
      if (gear == null) {
        await SyncService.instance.saveGear(result);
      } else {
        await SyncService.instance.updateGear(result);
      }
      await _load();
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern der Ausrüstung: $e');
      messenger.showSnackBar(SnackBar(
        content: Text(l.gearOfflineHint),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _delete(Gear gear) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.gearDeleteTitle),
        content: Text(l.gearDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || gear.id == null) return;

    try {
      await SyncService.instance.deleteGear(gear.id!);
      await _load();
    } catch (e) {
      appLogger.e('❌ Fehler beim Löschen der Ausrüstung: $e');
    }
  }

  Future<void> _toggleRetired(Gear gear) async {
    try {
      await SyncService.instance.updateGear(
        gear.copyWith(retired: !gear.retired),
      );
      await _load();
    } catch (e) {
      appLogger.e('❌ Fehler beim Ausmustern: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    // Retired gear sinks to the bottom: it keeps its history but is no longer
    // something the user picks from.
    final sorted = [..._gear]..sort((a, b) {
        if (a.retired != b.retired) return a.retired ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(title: Text(l.gearTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(l.gearAdd),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : sorted.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l.gearEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                        12, 12, 12, 88 + MediaQuery.paddingOf(context).bottom),
                    itemCount: sorted.length,
                    itemBuilder: (context, i) => _GearCard(
                      gear: sorted[i],
                      totals: _totals[sorted[i].id],
                      onEdit: () => _edit(gear: sorted[i]),
                      onDelete: () => _delete(sorted[i]),
                      onToggleRetired: () => _toggleRetired(sorted[i]),
                    ),
                  ),
                ),
    );
  }
}

class _GearCard extends StatelessWidget {
  final Gear gear;
  final GearTotals? totals;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleRetired;

  const _GearCard({
    required this.gear,
    required this.totals,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleRetired,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final t = totals ?? GearTotals(gearId: gear.id ?? '');
    final wear = t.wearFraction(gear.retireAtKm);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: gear.retired ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(gear.category.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      gear.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (gear.retired)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Text(l.gearRetired,
                            style: theme.textTheme.labelSmall),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit();
                        case 'retire':
                          onToggleRetired();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(l.edit)),
                      PopupMenuItem(
                        value: 'retire',
                        child: Text(gear.retired ? l.gearUnretire : l.gearRetire),
                      ),
                      PopupMenuItem(value: 'delete', child: Text(l.delete)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.gearStats(
                  t.totalDistanceKm.toStringAsFixed(1),
                  (t.totalMinutes / 60).toStringAsFixed(1),
                  t.activityCount,
                ),
                style: theme.textTheme.bodyMedium,
              ),
              if (wear != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: wear.clamp(0.0, 1.0),
                  minHeight: 6,
                  // Past the wear budget the bar turns red — that's the whole
                  // point of setting one.
                  color: wear >= 1.0
                      ? Colors.red
                      : wear >= 0.8
                          ? Colors.orange
                          : theme.colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  l.gearWearBudget(
                    t.totalDistanceKm.toStringAsFixed(0),
                    gear.retireAtKm!.toStringAsFixed(0),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Create/edit dialog. Returns the edited [Gear] (with the original id when
/// editing), or null on cancel.
class _GearEditDialog extends StatefulWidget {
  final Gear? gear;

  const _GearEditDialog({this.gear});

  @override
  State<_GearEditDialog> createState() => _GearEditDialogState();
}

class _GearEditDialogState extends State<_GearEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _initialDistanceController;
  late final TextEditingController _retireAtController;

  late GearCategory _category;
  ActivityType? _defaultActivityType;

  /// Types worth auto-attaching gear to. The rest (yoga, weight training, …)
  /// have no distance and no equipment worth tracking wear on.
  static const _autoAttachTypes = [
    ActivityType.running,
    ActivityType.walking,
    ActivityType.hiking,
    ActivityType.cycling,
    ActivityType.swimming,
  ];

  @override
  void initState() {
    super.initState();
    final g = widget.gear;
    _nameController = TextEditingController(text: g?.name ?? '');
    _initialDistanceController = TextEditingController(
      text: (g == null || g.initialDistanceKm == 0)
          ? ''
          : g.initialDistanceKm.toStringAsFixed(0),
    );
    _retireAtController = TextEditingController(
      text: g?.retireAtKm?.toStringAsFixed(0) ?? '',
    );
    _category = g?.category ?? GearCategory.shoes;
    _defaultActivityType = g?.defaultActivityType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialDistanceController.dispose();
    _retireAtController.dispose();
    super.dispose();
  }

  String _categoryLabel(AppLocalizations l, GearCategory c) {
    switch (c) {
      case GearCategory.shoes:
        return l.gearCategoryShoes;
      case GearCategory.bike:
        return l.gearCategoryBike;
      case GearCategory.other:
        return l.gearCategoryOther;
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // tryParseDouble returns null for an empty/unparseable field, which is
    // exactly what "no wear budget" means; initial distance falls back to 0.
    final initial = _initialDistanceController.text.trim();
    final retireAt = _retireAtController.text.trim();

    Navigator.of(context).pop(
      Gear(
        id: widget.gear?.id,
        name: _nameController.text.trim(),
        category: _category,
        defaultActivityType: _defaultActivityType,
        initialDistanceKm: tryParseDouble(initial) ?? 0,
        retireAtKm: tryParseDouble(retireAt),
        retired: widget.gear?.retired ?? false,
        notes: widget.gear?.notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(widget.gear == null ? l.gearAdd : l.gearEdit),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l.gearNameLabel,
                  hintText: l.gearNameHint,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? l.requiredField
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<GearCategory>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: l.gearCategory,
                  border: const OutlineInputBorder(),
                ),
                items: GearCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(c.icon, size: 20),
                              const SizedBox(width: 8),
                              Text(_categoryLabel(l, c)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ActivityType?>(
                initialValue: _defaultActivityType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.gearDefaultActivity,
                  helperText: l.gearDefaultActivityHelp,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.gearNone)),
                  ..._autoAttachTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Icon(t.icon, size: 20),
                            const SizedBox(width: 8),
                            Text(t.displayName),
                          ],
                        ),
                      )),
                ],
                onChanged: (v) => setState(() => _defaultActivityType = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _initialDistanceController,
                decoration: InputDecoration(
                  labelText: l.gearInitialDistance,
                  helperText: l.gearInitialDistanceHelp,
                  helperMaxLines: 2,
                  suffixText: 'km',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _retireAtController,
                decoration: InputDecoration(
                  labelText: l.gearRetireAt,
                  helperText: l.gearRetireAtHelp,
                  helperMaxLines: 2,
                  suffixText: 'km',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        ElevatedButton(onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}
