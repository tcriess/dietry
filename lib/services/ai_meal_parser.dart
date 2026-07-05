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

  @override
  Future<List<ParsedMealItem>> parse(String text) async {
    final output = await _generate(buildPrompt(text));
    return parseResponse(output);
  }

  /// The instruction prompt. Few-shot, strict-JSON, language-preserving.
  static String buildPrompt(String description) {
    return '''
You extract foods from a meal description. Return ONLY a JSON array, no prose.
Each element is {"food": string, "quantity": number, "unit": string or null}.
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
      final unit =
          (unitRaw != null && allowedUnits.contains(unitRaw)) ? unitRaw : null;

      items.add(ParsedMealItem(query: food, quantity: qty, portion: unit));
    }
    if (items.isEmpty) {
      throw const FormatException('No valid items in model output');
    }
    return items;
  }
}
