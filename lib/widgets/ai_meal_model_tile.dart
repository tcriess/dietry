import 'package:flutter/material.dart';
import 'package:dietry_cloud/dietry_cloud.dart' show premiumFeatures;

import '../l10n/app_localizations.dart';

/// Settings tile that manages the opt-in on-device LLM for "describe your meal"
/// AI parsing: download it (with progress), see it's ready, or remove it.
/// Only shown when [AppFeatures.aiMealParsing] is true (Pro + mobile).
class AiMealModelTile extends StatefulWidget {
  const AiMealModelTile({super.key});

  @override
  State<AiMealModelTile> createState() => _AiMealModelTileState();
}

class _AiMealModelTileState extends State<AiMealModelTile> {
  bool _loading = true;
  bool _downloaded = false;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final d = await premiumFeatures.isModelDownloaded();
    if (mounted) {
      setState(() {
        _downloaded = d;
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await premiumFeatures.downloadModel(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _downloaded = true);
    } catch (_) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.aiModelDownloadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    await premiumFeatures.deleteModel();
    if (mounted) {
      setState(() {
        _downloaded = false;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.aiMealTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (_downloaded && !_busy)
                  Chip(
                    label: Text(l.aiMealReady),
                    avatar: const Icon(Icons.check, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.aiMealDescription,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 12),
            _buildControl(l),
          ],
        ),
      ),
    );
  }

  Widget _buildControl(AppLocalizations l) {
    if (_loading) {
      return const Center(
        child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_busy && !_downloaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: 4),
          Text('${l.aiMealDownloading} ${(_progress * 100).round()}%',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      );
    }
    if (_downloaded) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: Text(l.aiMealRemove),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: _download,
        icon: const Icon(Icons.download),
        label: Text(l.aiMealEnable),
      ),
    );
  }
}
