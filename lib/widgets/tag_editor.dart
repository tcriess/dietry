import 'package:flutter/material.dart';
import 'package:dietry/models/tag.dart';
import 'package:dietry/services/tag_service.dart';
import 'package:dietry/services/app_logger.dart';
import 'package:dietry/l10n/app_localizations.dart';

/// Reusable widget for editing a list of tags
///
/// Shows existing tags as dismissible Chips in a Wrap.
/// If not readOnly, shows an "Add tag" ActionChip to add new tags.
/// Uses TagService for tag suggestions and creation.
class TagEditor extends StatefulWidget {
  /// Current list of tags
  final List<Tag> tags;

  /// Callback when tags change
  final Function(List<Tag>) onChanged;

  /// If true, tags are displayed but cannot be edited
  final bool readOnly;

  /// TagService instance for CRUD operations
  final TagService tagService;

  const TagEditor({
    super.key,
    required this.tags,
    required this.onChanged,
    required this.tagService,
    this.readOnly = false,
  });

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late List<Tag> _currentTags;
  late TextEditingController _autocompleteController;

  @override
  void initState() {
    super.initState();
    _currentTags = List.from(widget.tags);
  }

  @override
  void didUpdateWidget(TagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update internal tags if parent passed new tags
    if (oldWidget.tags.length != widget.tags.length ||
        !oldWidget.tags.every((tag) => widget.tags.any((t) => t.id == tag.id))) {
      setState(() => _currentTags = List.from(widget.tags));
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _addTag(String tagName) async {
    if (tagName.isEmpty) return;

    appLogger.d('🏷️ Hinzufügen oder Erstellen von Tag: "$tagName"');

    final newTag = await widget.tagService.getOrCreateTag(tagName);
    if (newTag == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Tag erstellen')),
        );
      }
      return;
    }

    // Check if tag already in list
    if (_currentTags.any((t) => t.id == newTag.id)) {
      appLogger.w('⚠️ Tag bereits hinzugefügt: ${newTag.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newTag.name} bereits hinzugefügt')),
        );
      }
      return;
    }

    setState(() {
      _currentTags.add(newTag);
      _autocompleteController.clear();
    });

    widget.onChanged(_currentTags);
    appLogger.i('✅ Tag hinzugefügt: ${newTag.name}');
  }

  void _removeTag(Tag tag) {
    appLogger.d('🗑️ Entferne Tag: ${tag.name}');
    setState(() {
      _currentTags.removeWhere((t) => t.id == tag.id);
    });
    widget.onChanged(_currentTags);
  }

  Future<List<Tag>> _getFilteredSuggestions(String query) async {
    if (query.isEmpty) return [];

    final suggestions = await widget.tagService.fetchTagSuggestions(query);

    // Filter out tags already added
    final filtered = suggestions
        .where((tag) => !_currentTags.any((t) => t.id == tag.id))
        .toList();

    appLogger.d('💡 TagEditor suggestions: ${filtered.length} found for "$query"');
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display existing tags
        if (_currentTags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _currentTags.map((tag) {
              return Chip(
                label: Text(tag.name),
                onDeleted: widget.readOnly ? null : () => _removeTag(tag),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              );
            }).toList(),
          ),
        if (_currentTags.isNotEmpty && !widget.readOnly) const SizedBox(height: 12),
        // Add tag input (only if not readOnly)
        if (!widget.readOnly)
          Autocomplete<Tag>(
            displayStringForOption: (Tag option) => option.name,
            optionsBuilder: (TextEditingValue textEditingValue) async {
              return await _getFilteredSuggestions(textEditingValue.text);
            },
            onSelected: (Tag selectedTag) {
              _addTag(selectedTag.name);
            },
            fieldViewBuilder: (BuildContext context,
                TextEditingController textEditingController,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted) {
              // Store reference to Autocomplete's controller so we can clear it from _addTag
              _autocompleteController = textEditingController;

              final l = AppLocalizations.of(context);
              return TextField(
                controller: textEditingController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: l?.tagHint ?? 'e.g., vegetarian, vegan, raw...',
                  prefixIcon: const Icon(Icons.label_outline),
                  suffixIcon: textEditingController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _addTag(textEditingController.text),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (String value) {
                  if (value.isNotEmpty) {
                    _addTag(value);
                  }
                },
                onChanged: (String value) {
                  // Rebuild to update suffix icon visibility
                  setState(() {});
                },
              );
            },
            optionsViewBuilder: (BuildContext context,
                AutocompleteOnSelected<Tag> onSelected,
                Iterable<Tag> options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: SizedBox(
                    width: 300,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Tag option = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(option.name),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
