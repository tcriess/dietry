import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:dietry_cloud/dietry_cloud.dart' show premiumFeatures;
import 'package:speech_to_text/speech_to_text.dart';

import '../app_features.dart';
import '../l10n/app_localizations.dart';
import '../models/food_entry.dart';
import '../models/food_item.dart';
import '../services/ai_meal_parser.dart';
import '../services/app_logger.dart';
import '../services/data_store.dart';
import '../services/food_database_service.dart';
import '../services/meal_parser.dart';
import '../services/meal_suggestion_service.dart';
import '../services/neon_database_service.dart';
import '../services/sync_service.dart';
import 'food_database_screen.dart';

/// "Describe your meal" — the user types (or dictates) a free-text meal, we
/// parse + fuzzy-match it into draft entries (auto-tagged uncertain) and let
/// them review, tweak the grams, and log them.
class MealDescriptionScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final DateTime? selectedDate;
  final MealType? initialMealType;

  const MealDescriptionScreen({
    super.key,
    this.dbService,
    this.selectedDate,
    this.initialMealType,
  });

  @override
  State<MealDescriptionScreen> createState() => _MealDescriptionScreenState();
}

class _MealDescriptionScreenState extends State<MealDescriptionScreen> {
  final _descCtrl = TextEditingController();
  late MealType _mealType;
  final List<_Row> _rows = [];
  bool _loading = false;
  bool _parsed = false;

  /// Whether the last parse actually used the on-device LLM (vs the heuristic
  /// / fallback) — surfaced as a small badge so it's visible which ran.
  bool _usedAi = false;

  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;

  /// Whether the Pro on-device LLM is downloaded & ready (checked once on open).
  bool _aiReady = false;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMealType ?? _mealForHour();
    if (AppFeatures.aiMealParsing && premiumFeatures.hasLocalLlm) {
      premiumFeatures.isModelDownloaded().then((ready) {
        if (mounted && ready) setState(() => _aiReady = true);
      });
    }
  }

  static MealType _mealForHour() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 10) return MealType.breakfast;
    if (h >= 10 && h < 14) return MealType.lunch;
    if (h >= 14 && h < 18) return MealType.snack;
    return MealType.dinner;
  }

  @override
  void dispose() {
    _speech.cancel();
    _descCtrl.dispose();
    for (final r in _rows) {
      r.gramsCtrl.dispose();
    }
    super.dispose();
  }

  /// Platforms where speech_to_text has an implementation. Linux/Windows
  /// desktop have none, so the mic button is hidden there (web-safe: uses
  /// defaultTargetPlatform, never dart:io). Web browsers do support it.
  bool get _voiceSupported {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  /// Map the app locale to a speech recognizer locale for better accuracy.
  String _speechLocale() {
    switch (Localizations.localeOf(context).languageCode) {
      case 'de':
        return 'de_DE';
      case 'es':
        return 'es_ES';
      default:
        return 'en_US';
    }
  }

  Future<void> _toggleListen() async {
    // Capture context-derived refs up front so nothing touches context across
    // the awaits below.
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    final localeId = _speechLocale();

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && mounted) {
              setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      } catch (_) {
        _speechReady = false; // no plugin/recognizer on this platform
      }
    }
    if (!_speechReady) {
      messenger.showSnackBar(SnackBar(content: Text(l.voiceUnavailable)));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions:
          SpeechListenOptions(partialResults: true, localeId: localeId),
      onResult: (r) {
        _descCtrl.text = r.recognizedWords;
        _descCtrl.selection =
            TextSelection.collapsed(offset: _descCtrl.text.length);
      },
    );
  }

  /// Which parser to use: the Pro on-device LLM when it's available & the model
  /// is downloaded, otherwise the offline heuristic (also the runtime fallback,
  /// see [_suggest]).
  MealParser _resolveParser() {
    if (_aiReady && AppFeatures.aiMealParsing && premiumFeatures.hasLocalLlm) {
      return AiMealParser((prompt) => premiumFeatures.generateText(prompt: prompt));
    }
    return const HeuristicMealParser();
  }

  Future<void> _suggest() async {
    final db = widget.dbService;
    if (db == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final foods = FoodDatabaseService(db);
    final parser = _resolveParser();
    final wantAi = parser is AiMealParser;
    appLogger.i('🍽️ describe-meal parse via ${wantAi ? "on-device LLM" : "heuristic"}');
    List<MealItemSuggestion> suggestions;
    var usedAi = false;
    try {
      suggestions = await MealSuggestionService(
        foods,
        parser: parser,
        // Second chance for items the food database cannot match. Only with the
        // on-device model: the search matches spelling, not meaning, so it can
        // never get from "gaspaccho" to a tomato soup — but the model knows what
        // gazpacho is. Without a model, an unmatched item just stays unmatched.
        aliasResolver: parser is AiMealParser ? parser.resolveAliases : null,
      ).suggest(_descCtrl.text);
      usedAi = wantAi;
    } catch (e) {
      // On-device LLM failed (or unparseable) → fall back to the heuristic.
      appLogger.w('⚠️ AI meal parse failed → heuristic fallback: $e');
      suggestions = await MealSuggestionService(foods).suggest(_descCtrl.text);
    }
    if (!mounted) return;
    for (final r in _rows) {
      r.gramsCtrl.dispose();
    }
    _rows
      ..clear()
      ..addAll(suggestions.map((s) => _Row(
            suggestion: s,
            gramsCtrl: TextEditingController(
                text: s.grams > 0 ? s.grams.round().toString() : ''),
            include: s.matched,
          )));
    setState(() {
      _loading = false;
      _parsed = true;
      _usedAi = usedAi;
    });
  }

  double _gramsOf(_Row r) =>
      double.tryParse(r.gramsCtrl.text.replaceAll(',', '.')) ?? 0;

  int get _selectedCount =>
      _rows.where((r) => r.include && r.suggestion.matched && _gramsOf(r) > 0)
          .length;

  Future<void> _addAll() async {
    final userId = widget.dbService?.userId;
    final date = widget.selectedDate ?? DateTime.now();
    if (userId == null) return;
    for (final r in _rows) {
      if (!r.include || !r.suggestion.matched) continue;
      final entry = r.suggestion.toFoodEntry(
        userId: userId,
        date: date,
        mealType: _mealType,
        gramsOverride: _gramsOf(r),
      );
      if (entry == null) continue;
      final saved = await SyncService.instance.createFoodEntry(entry);
      DataStore.instance.addFoodEntry(saved ?? entry);
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Opens the food editor prefilled with the item's name to create a new DB
  /// food, then makes this row a match for it. Available for unmatched items
  /// (nothing was found) and matched ones (in case the match is wrong).
  Future<void> _createFood(_Row row) async {
    final db = widget.dbService;
    if (db == null) return;
    final created = await showDialog<FoodItem>(
      context: context,
      builder: (_) => FoodEditDialog(
        food: null,
        dbService: db,
        initialName: row.suggestion.parsed.query,
      ),
    );
    if (created == null || !mounted) return;
    final FoodItem saved;
    try {
      saved = await FoodDatabaseService(db).createFood(created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!mounted) return;
    final parsed = row.suggestion.parsed;
    final grams = MealSuggestionService.resolveGrams(parsed, saved);
    setState(() {
      final idx = _rows.indexOf(row);
      if (idx < 0) return;
      row.gramsCtrl.dispose();
      _rows[idx] = _Row(
        suggestion:
            MealItemSuggestion(parsed: parsed, match: saved, grams: grams),
        gramsCtrl: TextEditingController(
            text: grams > 0 ? grams.round().toString() : ''),
        include: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.describeMealTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.describeMealIntro,
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: l.describeMealHint,
                    border: const OutlineInputBorder(),
                    suffixIcon: _voiceSupported
                        ? IconButton(
                            icon: Icon(_listening ? Icons.stop : Icons.mic,
                                color: _listening ? Colors.red : null),
                            tooltip: l.describeMealVoice,
                            onPressed: _toggleListen,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _suggest,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(l.describeMealSuggest),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults(l)),
        ],
      ),
      bottomNavigationBar: _parsed && _selectedCount > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _MealTypeDropdown(
                      value: _mealType,
                      onChanged: (m) => setState(() => _mealType = m),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addAll,
                        icon: const Icon(Icons.check),
                        label: Text('${l.describeMealAddAll} ($_selectedCount)'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildResults(AppLocalizations l) {
    if (!_parsed) return const SizedBox.shrink();
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.describeMealEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
    }
    return Column(
      children: [
        if (_usedAi)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: Colors.deepPurple),
                const SizedBox(width: 6),
                Text(l.aiMealTitle,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.deepPurple)),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _buildRow(l, _rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(AppLocalizations l, _Row r) {
    final s = r.suggestion;
    if (!s.matched) {
      return ListTile(
        leading: Icon(Icons.help_outline, color: Colors.grey.shade400),
        title: Text(s.parsed.query,
            style: TextStyle(color: Colors.grey.shade500)),
        subtitle: Text(l.describeMealNoMatch,
            style: TextStyle(color: Colors.grey.shade400)),
        trailing: TextButton.icon(
          onPressed: () => _createFood(r),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l.describeMealCreateFood),
        ),
      );
    }
    final grams = _gramsOf(r);
    final kcal = (s.match!.calories * grams / 100).round();
    return CheckboxListTile(
      value: r.include,
      onChanged: (v) => setState(() => r.include = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      // "Wrong match? create a new food instead."
      secondary: IconButton(
        icon: const Icon(Icons.add_circle_outline),
        tooltip: l.describeMealCreateFood,
        onPressed: () => _createFood(r),
      ),
      title: Row(
        children: [
          Flexible(child: Text(s.match!.name, overflow: TextOverflow.ellipsis)),
          // The food as typed was NOT found; this is a stand-in the model
          // suggested. Say so — logging "tomato soup" under the silent belief it
          // is gazpacho would misreport what the user actually ate.
          if (s.isSubstitute) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: l.describeMealSubstituteHint,
              child: Chip(
                label: Text(l.describeMealApproximate,
                    style: const TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.auto_awesome, size: 14),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.isSubstitute)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '“${s.parsed.query}” → ${s.matchedVia}',
                  style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                      fontStyle: FontStyle.italic),
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: r.gramsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      suffixText: 'g',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.isSubstitute
                        ? '$kcal kcal'
                        : '$kcal kcal · “${s.parsed.query}”',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  final MealItemSuggestion suggestion;
  final TextEditingController gramsCtrl;
  bool include;
  _Row({required this.suggestion, required this.gramsCtrl, this.include = true});
}

class _MealTypeDropdown extends StatelessWidget {
  final MealType value;
  final ValueChanged<MealType> onChanged;
  const _MealTypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DropdownButton<MealType>(
      value: value,
      onChanged: (m) => m == null ? null : onChanged(m),
      items: MealType.values
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text('${m.icon} ${m.localizedName(l)}'),
              ))
          .toList(),
    );
  }
}
