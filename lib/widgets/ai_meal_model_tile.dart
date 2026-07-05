import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_model_controller.dart';

/// Settings tile that manages the opt-in on-device LLM for "describe your meal".
/// It's a pure observer of [AiModelController] (a singleton), so scrolling it
/// out of view / rebuilding never disrupts an in-flight download or resets the
/// UI. Only shown when [AppFeatures.aiMealParsing] is true (Pro + mobile).
class AiMealModelTile extends StatefulWidget {
  const AiMealModelTile({super.key});

  @override
  State<AiMealModelTile> createState() => _AiMealModelTileState();
}

class _AiMealModelTileState extends State<AiMealModelTile> {
  final _c = AiModelController.instance;

  @override
  void initState() {
    super.initState();
    _c.ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _c.listenable,
      builder: (context, _) => Card(
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
                  if (_c.downloaded.value && !_c.isDownloading)
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
      ),
    );
  }

  Widget _buildControl(AppLocalizations l) {
    if (_c.isDownloading) {
      final p = _c.progress.value ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: p > 0 ? p : null),
          const SizedBox(height: 4),
          Text('${l.aiMealDownloading} ${(p * 100).round()}%',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      );
    }
    if (_c.downloaded.value) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _c.delete(),
          icon: const Icon(Icons.delete_outline),
          label: Text(l.aiMealRemove),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.failed.value)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.aiModelDownloadFailed,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _c.download(),
            icon: const Icon(Icons.download),
            label: Text(l.aiMealEnable),
          ),
        ),
      ],
    );
  }
}
