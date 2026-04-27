import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../app_config.dart';
import '../app_features.dart';
import '../services/feedback_service.dart';
import '../l10n/app_localizations.dart';

class FeedbackDialog extends StatefulWidget {
  final FeedbackService feedbackService;

  const FeedbackDialog({super.key, required this.feedbackService});

  static Future<void> show(BuildContext context, FeedbackService service) {
    return showDialog(
      context: context,
      builder: (_) => FeedbackDialog(feedbackService: service),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  FeedbackType _type = FeedbackType.general;
  int? _rating;
  final _messageController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.length < 10) {
      setState(() =>
          _errorText = AppLocalizations.of(context)!.feedbackMessageTooShort);
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      final hash = AppConfig.gitHash;
      final edition = AppConfig.isCloudEdition ? 'Cloud' : 'CE';
      final version = '${info.version}+${info.buildNumber} ($edition · $hash)';
      await widget.feedbackService.submitFeedback(
        type: _type,
        message: message,
        rating: _rating,
        appVersion: version,
        userRole: AppFeatures.role,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.feedbackThankYou),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorText = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          const Icon(Icons.feedback_outlined),
          const SizedBox(width: 8),
          Text(l.feedbackTitle),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.feedbackEarlyAccessNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 16),

            // Type chips
            Text(l.feedbackTypeLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _TypeChip(
                  label: l.feedbackTypeBug,
                  icon: Icons.bug_report_outlined,
                  value: FeedbackType.bug,
                  selected: _type,
                  onSelected: (t) => setState(() => _type = t),
                ),
                _TypeChip(
                  label: l.feedbackTypeFeature,
                  icon: Icons.lightbulb_outlined,
                  value: FeedbackType.feature,
                  selected: _type,
                  onSelected: (t) => setState(() => _type = t),
                ),
                _TypeChip(
                  label: l.feedbackTypeGeneral,
                  icon: Icons.chat_bubble_outline,
                  value: FeedbackType.general,
                  selected: _type,
                  onSelected: (t) => setState(() => _type = t),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Star rating
            Text(l.feedbackRatingLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  icon: Icon(
                    star <= (_rating ?? 0) ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                  onPressed: () => setState(
                    () => _rating = _rating == star ? null : star,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Message
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: l.feedbackMessageLabel,
                hintText: l.feedbackMessageHint,
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send),
          label: Text(l.feedbackSubmit),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final FeedbackType value;
  final FeedbackType selected;
  final ValueChanged<FeedbackType> onSelected;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return FilterChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
    );
  }
}
