import 'package:flutter/material.dart';

import '../app_features.dart';
import '../models/food_entry.dart';
import '../models/tag.dart';
import '../services/neon_database_service.dart';
import '../services/tag_service.dart';

/// The tags every food entry of the day shares (e.g. "vegan"), as chips.
/// Renders nothing when there are none.
class DayTagsRow extends StatefulWidget {
  final List<FoodEntry> entries;
  final NeonDatabaseService? dbService;

  const DayTagsRow({super.key, required this.entries, this.dbService});

  @override
  State<DayTagsRow> createState() => _DayTagsRowState();
}

class _DayTagsRowState extends State<DayTagsRow> {
  List<Tag> _tags = const [];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DayTagsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The store hands out a new list on every reload; refetch then, so tag
    // edits made elsewhere show up too.
    if (!identical(oldWidget.entries, widget.entries)) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final db = widget.dbService;
    final entries = widget.entries;
    if (db == null || entries.isEmpty) {
      if (_tags.isNotEmpty) setState(() => _tags = const []);
      return;
    }

    final service = TagService(db);
    final foodIds = [
      for (final e in entries)
        if (e.mealTemplateId == null && e.foodId != null) e.foodId!,
    ];
    final templateIds = [
      for (final e in entries)
        if (e.mealTemplateId != null) e.mealTemplateId!,
    ];
    final results = await Future.wait([
      service.getTagsForFoods(foodIds),
      AppFeatures.mealTemplates
          ? service.getTagsForMealTemplates(templateIds)
          : Future.value(const <String, List<Tag>>{}),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _tags = TagService.commonTags(entries,
          foodTags: results[0], templateTags: results[1]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tags.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tag in _tags)
            Chip(
              avatar: Icon(Icons.label_outline,
                  size: 16, color: scheme.onSecondaryContainer),
              label: Text(tag.name),
              labelStyle: TextStyle(
                  fontSize: 12, color: scheme.onSecondaryContainer),
              backgroundColor: scheme.secondaryContainer,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
