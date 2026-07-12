import 'dart:convert';

import 'meal_description_parser.dart';
import 'meal_parser.dart';

/// [MealParser] backed by an on-device LLM. It owns the prompt and the (robust)
/// JSON parsing; the actual text generation is injected as a [_generate]
/// closure so this class stays in CE and unit-testable — the heavy native
/// runtime lives in the cloud package and is passed in as a function reference.
///
/// On any failure (generation error, unparseable output) [parse] throws, and
/// the caller falls back to the offline [HeuristicMealParser].
class AiMealParser implements MealParser {
  final Future<String> Function(String prompt) _generate;

  const AiMealParser(this._generate);

  /// The units the model is allowed to emit — same vocabulary the heuristic
  /// parser and the grams-resolver understand.
  static const Set<String> allowedUnits = {
    'g', 'ml', 'plate', 'bowl', 'cup', 'glass', 'slice', 'handful',
    'piece', 'spoon', 'serving',
  };

  /// How long to wait for one on-device generation. SmolLM2-360M answers in a
  /// few seconds on a phone; past this the runtime is wedged, and there used to
  /// be no timeout anywhere in the chain — a stalled generation left the review
  /// screen spinning forever. On timeout [parse] throws and the caller falls
  /// back to the heuristic parser, exactly as for any other generation failure.
  static const Duration generateTimeout = Duration(seconds: 45);

  /// Most search terms worth trying for one unmatched food.
  static const int maxAliases = 5;

  @override
  Future<List<ParsedMealItem>> parse(String text) async {
    final output = await _generate(buildPrompt(text)).timeout(generateTimeout);
    return parseResponse(output);
  }

  /// Second pass, for a food the database could not match: ask the model what it
  /// *is*, and search for that instead.
  ///
  /// This exists because fuzzy search matches spelling, not meaning, and cannot
  /// bridge the two. "gaspaccho" has a word_similarity of 0.357 to "gazpacho" —
  /// below any threshold that does not also flood the results with junk — so no
  /// amount of trigram tuning finds it. The model, however, knows what gazpacho
  /// is, and "cold tomato soup" is a perfectly good stand-in for logging.
  ///
  /// Returns candidate search terms, closest first: other names for the whole
  /// dish, then its main ingredients. Empty when the model gives nothing usable.
  Future<List<String>> resolveAliases(String foodName) async {
    final output =
        await _generate(buildAliasPrompt(foodName)).timeout(generateTimeout);
    return parseAliases(output, original: foodName);
  }

  /// The instruction prompt. Few-shot, strict-JSON, language-preserving.
  static String buildPrompt(String description) {
    return '''
You extract foods from a meal description. Return ONLY a JSON array, no prose.
Each element is {"food": string, "quantity": number, "unit": string or null}.
"food" is the food NAME ONLY — never put numbers or unit words in it.
"unit" must be one of: g, ml, plate, bowl, cup, glass, slice, handful, piece,
spoon, serving — or null for a bare count. Keep food names in the description's
language.

Description: "rice with paprika and peas, two plates"
[{"food":"rice","quantity":2,"unit":"plate"},{"food":"paprika","quantity":2,"unit":"plate"},{"food":"peas","quantity":2,"unit":"plate"}]

Description: "200g chicken and a glass of milk"
[{"food":"chicken","quantity":200,"unit":"g"},{"food":"milk","quantity":1,"unit":"glass"}]

Description: "${description.replaceAll('"', "'").trim()}"
''';
  }

  /// Prompt for [resolveAliases]. Ordered deliberately: a different name for the
  /// same dish is a far better log entry than a pile of raw ingredients, so ask
  /// for those first and let the ingredients be the fallback within the fallback.
  static String buildAliasPrompt(String foodName) {
    return '''
The food "${foodName.replaceAll('"', "'").trim()}" was not found in a nutrition database.
List up to $maxAliases search terms for it, closest first: first other common names
for the whole dish, then its main ingredients. Return ONLY a JSON array of
strings. Keep the terms in the food's language.

Food: "lasagne"
["lasagna","pasta bake","tomato sauce","ground beef","cheese"]

Food: "gazpacho"
["cold tomato soup","tomato soup","tomato","cucumber","bell pepper"]

Food: "${foodName.replaceAll('"', "'").trim()}"
''';
  }

  /// Extract search terms from the alias prompt's output. Same tolerance as
  /// [parseResponse] (reasoning blocks, prose around the array), plus: each term
  /// is run through the heuristic parser so a model that answers "a bowl of
  /// tomato soup" still yields the searchable "tomato soup". Terms equal to
  /// [original] are dropped — re-searching the name that already failed is a
  /// wasted round trip.
  ///
  /// Returns an empty list rather than throwing: a failed alias lookup is not an
  /// error, it just means the item stays unmatched.
  static List<String> parseAliases(String raw, {required String original}) {
    final thinkEnd = raw.lastIndexOf('</think>');
    final String body;
    if (thinkEnd >= 0) {
      body = raw.substring(thinkEnd + '</think>'.length);
    } else if (raw.contains('<think>')) {
      return const [];
    } else {
      body = raw;
    }

    final start = body.indexOf('[');
    final end = body.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(body.substring(start, end + 1));
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final originalKey = original.trim().toLowerCase();
    final out = <String>[];
    final seen = <String>{};
    for (final e in decoded) {
      if (e is! String) continue;
      var term = e.trim();
      if (term.isEmpty) continue;

      // "a bowl of tomato soup" -> "tomato soup"
      final cleaned = MealDescriptionParser.parse(term);
      if (cleaned.length == 1 && cleaned.first.query.isNotEmpty) {
        term = cleaned.first.query;
      }

      final key = term.toLowerCase();
      if (key == originalKey) continue; // already tried, it is why we are here
      if (seen.add(key)) out.add(term);
      if (out.length >= maxAliases) break;
    }
    return out;
  }

  /// Extract items from raw model output. Tolerant of code fences and prose
  /// around the array, `name`/`food` key variants, and string quantities;
  /// unknown units become null. Throws [FormatException] when nothing usable is
  /// found (→ caller falls back to the heuristic parser).
  static List<ParsedMealItem> parseResponse(String raw) {
    // Reasoning models (e.g. Qwen3) may prepend a <think>...</think> monologue.
    // Parse only the answer after it. If a <think> opened but never closed, the
    // output was truncated mid-reasoning — bail cleanly rather than mistake a
    // bracket in the monologue (or an echoed example) for the answer.
    final thinkEnd = raw.lastIndexOf('</think>');
    final String body;
    if (thinkEnd >= 0) {
      body = raw.substring(thinkEnd + '</think>'.length);
    } else if (raw.contains('<think>')) {
      throw const FormatException('Model output was cut off during reasoning');
    } else {
      body = raw;
    }

    final start = body.indexOf('[');
    final end = body.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const FormatException('No JSON array in model output');
    }
    final decoded = jsonDecode(body.substring(start, end + 1));
    if (decoded is! List) {
      throw const FormatException('Model output is not a JSON array');
    }

    final items = <ParsedMealItem>[];
    final seen = <String>{};
    for (final e in decoded) {
      if (e is! Map) continue;
      final food = (e['food'] ?? e['name'])?.toString().trim();
      if (food == null || food.isEmpty) continue;

      final qtyRaw = e['quantity'] ?? e['qty'] ?? e['amount'];
      double qty = 1;
      if (qtyRaw is num) {
        qty = qtyRaw.toDouble();
      } else if (qtyRaw is String) {
        qty = double.tryParse(qtyRaw.replaceAll(',', '.')) ?? 1;
      }
      if (qty <= 0) qty = 1;

      final unitRaw = e['unit']?.toString().trim().toLowerCase();
      String? unit =
          (unitRaw != null && allowedUnits.contains(unitRaw)) ? unitRaw : null;

      // Small models often cram the quantity/unit into the food name
      // ("2 Teller Gaspacho") or use a localized unit ("teller"). Run the name
      // through the heuristic parser to recover a clean name + the real
      // quantity/portion it can't express.
      String query = food;
      final cleaned = MealDescriptionParser.parse(food);
      if (cleaned.length == 1 && cleaned.first.query.isNotEmpty) {
        query = cleaned.first.query;
        if (qty == 1 && cleaned.first.quantity != 1) qty = cleaned.first.quantity;
        unit ??= cleaned.first.portion;
      }

      // De-dupe (small models sometimes repeat the same item).
      if (seen.add('$query|$qty|$unit')) {
        items.add(ParsedMealItem(query: query, quantity: qty, portion: unit));
      }
    }
    if (items.isEmpty) {
      throw const FormatException('No valid items in model output');
    }
    return items;
  }
}
