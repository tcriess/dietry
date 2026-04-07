import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/activity_item.dart';
import '../services/activity_database_service.dart';
import '../services/neon_database_service.dart';
import '../l10n/app_localizations.dart';

/// Screen zur Verwaltung eigener Aktivitäten in der Datenbank.
///
/// Listet alle eigenen Einträge (privat + ausstehend public + approved public)
/// mit Edit/Delete. Tippen auf einen Eintrag gibt ihn als Pop-Ergebnis zurück
/// (für Auswahl in AddActivityScreen).
class ActivityDatabaseScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const ActivityDatabaseScreen({super.key, required this.dbService});

  @override
  State<ActivityDatabaseScreen> createState() => _ActivityDatabaseScreenState();
}

class _ActivityDatabaseScreenState extends State<ActivityDatabaseScreen> {
  List<ActivityItem> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() => _isLoading = true);
    try {
      final service = ActivityDatabaseService(widget.dbService);
      final activities = await service.getMyActivities();
      if (mounted) setState(() => _activities = activities);
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

  Future<void> _editActivity(ActivityItem activity) async {
    final result = await showDialog<ActivityItem>(
      context: context,
      builder: (context) => ActivityEditDialog(
        activity: activity,
        isEditing: true,
      ),
    );
    if (result != null) {
      try {
        final service = ActivityDatabaseService(widget.dbService);
        await service.updateActivity(result);
        if (mounted) {
          final l = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.entryUpdated), backgroundColor: Colors.green),
          );
          _loadActivities();
        }
      } catch (e) {
        if (mounted) {
          final l = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleFavourite(ActivityItem activity) async {
    final newValue = !activity.isFavourite;
    setState(() {
      final idx = _activities.indexWhere((a) => a.id == activity.id);
      if (idx != -1) {
        // ActivityItem has no copyWith; rebuild manually
        _activities[idx] = ActivityItem(
          id: activity.id,
          userId: activity.userId,
          name: activity.name,
          metValue: activity.metValue,
          category: activity.category,
          intensity: activity.intensity,
          description: activity.description,
          avgSpeedKmh: activity.avgSpeedKmh,
          isPublic: activity.isPublic,
          isApproved: activity.isApproved,
          isFavourite: newValue,
          source: activity.source,
          createdAt: activity.createdAt,
          updatedAt: activity.updatedAt,
        );
      }
    });
    try {
      await ActivityDatabaseService(widget.dbService)
          .toggleActivityFavourite(activity.id, isFavourite: newValue);
    } catch (e) {
      // Revert on error
      setState(() {
        final idx = _activities.indexWhere((a) => a.id == activity.id);
        if (idx != -1) _activities[idx] = activity;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteActivity(ActivityItem activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l.deleteActivityTitle),
          content: Text(l.deleteActivityConfirm(activity.name)),
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
      final service = ActivityDatabaseService(widget.dbService);
      await service.deleteActivity(activity.id);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.activityDeleted), backgroundColor: Colors.green),
        );
        _loadActivities();
      }
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
      appBar: AppBar(title: Text(l.myActivities)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fitness_center, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        l.activitiesEmpty,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.activitiesEmptyHint,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _activities.length,
                  itemBuilder: (context, index) {
                    final activity = _activities[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: Text(
                          activity.categoryIcon,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      title: Text(activity.name),
                      subtitle: Text(
                        'MET ${activity.metValue.toStringAsFixed(1)}'
                        '${activity.category != null ? ' • ${activity.category}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Freigabe-Status
                          if (activity.isPublic)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: Text(
                                  activity.isApproved ? l.statusPublic : l.statusPending,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: activity.isApproved
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              activity.isFavourite
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 20,
                              color: activity.isFavourite
                                  ? Colors.amber.shade600
                                  : Colors.grey.shade400,
                            ),
                            tooltip: activity.isFavourite
                                ? 'Aus Favoriten entfernen'
                                : 'Als Favorit markieren',
                            onPressed: () => _toggleFavourite(activity),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _editActivity(activity);
                              if (value == 'delete') _deleteActivity(activity);
                            },
                            itemBuilder: (context) {
                              final lp = AppLocalizations.of(context)!;
                              return [
                                PopupMenuItem(value: 'edit', child: Text(lp.edit)),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(lp.delete, style: const TextStyle(color: Colors.red)),
                                ),
                              ];
                            },
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(activity),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final l = AppLocalizations.of(context)!;
          final result = await showDialog<ActivityItem>(
            context: context,
            builder: (context) => const ActivityEditDialog(
              activity: null,
              isEditing: false,
            ),
          );
          if (result != null) {
            try {
              final service = ActivityDatabaseService(widget.dbService);
              final created = await service.createActivity(result);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l.foodAdded(created.name)),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadActivities();
              }
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l.errorPrefix(e.toString())), backgroundColor: Colors.red),
                );
              }
            }
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Dialog zum Erstellen oder Bearbeiten einer Activity in der Datenbank.
///
/// Wird auch von [AddActivityScreen] verwendet.
class ActivityEditDialog extends StatefulWidget {
  final ActivityItem? activity;
  final bool isEditing;

  const ActivityEditDialog({
    super.key,
    required this.activity,
    required this.isEditing,
  });

  @override
  ActivityEditDialogState createState() => ActivityEditDialogState();
}

class ActivityEditDialogState extends State<ActivityEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _metValueController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _avgSpeedController;
  late String _intensity;
  late bool _isPublic;

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    _nameController = TextEditingController(text: a?.name ?? '');
    _metValueController = TextEditingController(
      text: a != null ? a.metValue.toStringAsFixed(1) : '3.5',
    );
    _categoryController = TextEditingController(text: a?.category ?? '');
    _descriptionController = TextEditingController(text: a?.description ?? '');
    _avgSpeedController = TextEditingController(
      text: a?.avgSpeedKmh != null ? a!.avgSpeedKmh!.toStringAsFixed(1) : '',
    );
    _intensity = a?.intensity ?? 'moderate';
    _isPublic = a?.isPublic ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _metValueController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _avgSpeedController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final activity = ActivityItem(
      id: widget.activity?.id ?? '',
      userId: widget.activity?.userId,
      name: _nameController.text.trim(),
      metValue: double.parse(_metValueController.text),
      category: _categoryController.text.isNotEmpty ? _categoryController.text.trim() : null,
      intensity: _intensity,
      description: _descriptionController.text.isNotEmpty ? _descriptionController.text.trim() : null,
      avgSpeedKmh: _avgSpeedController.text.isNotEmpty
          ? double.tryParse(_avgSpeedController.text)
          : null,
      isPublic: _isPublic,
      isApproved: false,  // Immer zurücksetzen beim Speichern
      source: widget.activity?.source ?? 'Custom',
      createdAt: widget.activity?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop(activity);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.isEditing ? l.editMeasurementTitle : l.saveToDatabase),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warnung bei Bearbeitung eines bereits freigegebenen Eintrags
              if (widget.isEditing && widget.activity?.isApproved == true)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dieser Eintrag ist öffentlich freigegeben. Eine Bearbeitung setzt die Freigabe zurück.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),

              // Info MET
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
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
                        'MET = Vielfaches des Ruheenergieverbrauchs',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),

              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? l.requiredField : null,
              ),

              const SizedBox(height: 12),

              // MET-Wert
              TextFormField(
                controller: _metValueController,
                decoration: const InputDecoration(
                  labelText: 'MET-Wert *',
                  hintText: 'z.B. 3.5 für Gehen',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) return l.requiredField;
                  final met = double.tryParse(value);
                  if (met == null || met <= 0) return l.weightInvalid;
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // Kategorie
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Kategorie (optional)',
                  hintText: 'z.B. Ausdauer, Kraft, Sport',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Intensität
              DropdownButtonFormField<String>(
                initialValue: _intensity,
                decoration: const InputDecoration(
                  labelText: 'Intensität',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Niedrig')),
                  DropdownMenuItem(value: 'moderate', child: Text('Moderat')),
                  DropdownMenuItem(value: 'high', child: Text('Hoch')),
                  DropdownMenuItem(value: 'very_high', child: Text('Sehr Hoch')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _intensity = value);
                },
              ),

              const SizedBox(height: 12),

              // Beschreibung
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 12),

              // Durchschn. Geschwindigkeit
              TextFormField(
                controller: _avgSpeedController,
                decoration: const InputDecoration(
                  labelText: 'Durchschn. Geschwindigkeit (optional)',
                  suffixText: 'km/h',
                  hintText: 'Für Distanz-Schätzung',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
              ),

              const SizedBox(height: 4),

              // Öffentlich-Switch
              SwitchListTile(
                title: const Text('Für alle Nutzer sichtbar'),
                subtitle: const Text('Erfordert Admin-Freigabe'),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
                contentPadding: EdgeInsets.zero,
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
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.isEditing ? l.save : l.add),
        ),
      ],
    );
  }
}
