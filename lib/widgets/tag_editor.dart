import 'package:flutter/material.dart';
import 'package:dietry/models/tag.dart';
import 'package:dietry/services/tag_service.dart';
import 'package:dietry/services/app_logger.dart';

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
  late TextEditingController _inputController;
  late FocusNode _inputFocus;
  List<Tag> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _currentTags = List.from(widget.tags);
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _onInputChanged() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) {
      setState(() => _showSuggestions = false);
      return;
    }

    // Fetch suggestions from service
    final suggestions = await widget.tagService.fetchTagSuggestions(query);

    // Filter out tags already added
    final filtered = suggestions
        .where((tag) => !_currentTags.any((t) => t.id == tag.id))
        .toList();

    setState(() {
      _suggestions = filtered;
      _showSuggestions = true;
    });
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
      _inputController.clear();
      _inputFocus.requestFocus();
      return;
    }

    setState(() {
      _currentTags.add(newTag);
      _suggestions = [];
      _showSuggestions = false;
      _inputController.clear();
    });

    widget.onChanged(_currentTags);
    appLogger.i('✅ Tag hinzugefügt: ${newTag.name}');

    if (mounted) {
      _inputFocus.requestFocus();
    }
  }

  void _removeTag(Tag tag) {
    appLogger.d('🗑️ Entferne Tag: ${tag.name}');
    setState(() {
      _currentTags.removeWhere((t) => t.id == tag.id);
    });
    widget.onChanged(_currentTags);
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Input field with suggestions dropdown
              TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                decoration: InputDecoration(
                  hintText: 'z.B. vegetarisch, vegan, roh',
                  prefixIcon: const Icon(Icons.label_outline),
                  suffixIcon: _inputController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _addTag(_inputController.text),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: _addTag,
              ),
              // Suggestions dropdown
              if (_showSuggestions && _suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final tag = _suggestions[index];
                      return ListTile(
                        title: Text(tag.name),
                        dense: true,
                        onTap: () => _addTag(tag.name),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
