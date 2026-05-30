import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/neon_database_service.dart';
import '../services/tag_service.dart';

/// Lets the user review the tags they created and delete them globally.
///
/// Deleting a tag removes it from the shared `tags` pool and — via the
/// ON DELETE CASCADE on `user_food_tags` — from every food it was applied to,
/// so it disappears from suggestions and filters for everyone.
///
/// Pops with `true` when at least one tag was deleted, so the opener can
/// refresh its available-tag list.
class TagManagementScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const TagManagementScreen({super.key, required this.dbService});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  late final TagService _tagService;
  List<ManagedTag> _tags = [];
  bool _isLoading = true;
  bool _didChange = false;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _tagService = TagService(widget.dbService);
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() => _isLoading = true);
    final tags = await _tagService.getMyTags();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(ManagedTag managed) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteTagTitle),
        content: Text(l.deleteTagConfirm(managed.tag.name, managed.usageCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = managed.tag.id);
    final ok = await _tagService.deleteTag(managed.tag.id);
    if (!mounted) return;
    setState(() => _deletingId = null);

    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      _didChange = true;
      setState(() => _tags.removeWhere((t) => t.tag.id == managed.tag.id));
      messenger.showSnackBar(SnackBar(content: Text(l.tagDeleted)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.tagDeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_didChange);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.manageTags)),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _tags.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l.noTagsCreated,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadTags,
                    child: ListView.separated(
                      itemCount: _tags.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final managed = _tags[i];
                        final isDeleting = _deletingId == managed.tag.id;
                        return ListTile(
                          leading: const Icon(Icons.sell_outlined),
                          title: Text(managed.tag.name),
                          subtitle: Text(l.tagUsageCount(managed.usageCount)),
                          trailing: isDeleting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.red,
                                  onPressed: () => _confirmDelete(managed),
                                ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
