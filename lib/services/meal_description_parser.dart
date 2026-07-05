/// Heuristic, fully-offline parser that turns a free-text meal description
/// ("rice with paprika and peas, two plates") into rough item suggestions
/// (food name + quantity + portion word).
///
/// It does NOT touch the database: the caller matches each [ParsedMealItem.query]
/// via fuzzy food search and builds the draft entries — auto-tagged uncertain,
/// since a spoken/typed description is inherently a rough estimate.
///
/// Multilingual (en/de/es — the app's shipped locales). Deliberately forgiving:
/// anything it can't structure falls back to "the whole phrase is one item,
/// quantity 1". The output is a *suggestion the user confirms*, not ground truth.
library;

/// One parsed item from a meal description.
class ParsedMealItem {
  /// The food name to look up (separators / quantities / units stripped).
  final String query;

  /// How many [portion]s (or bare count when [portion] is null). Defaults to 1.
  final double quantity;

  /// Normalized portion/unit token: 'g', 'ml', 'plate', 'bowl', 'cup', 'glass',
  /// 'slice', 'handful', 'piece', 'spoon', 'serving' — or null (bare count).
  final String? portion;

  const ParsedMealItem({
    required this.query,
    this.quantity = 1,
    this.portion,
  });

  @override
  String toString() =>
      'ParsedMealItem($quantity ${portion ?? ''} "$query")'.replaceAll('  ', ' ');

  @override
  bool operator ==(Object other) =>
      other is ParsedMealItem &&
      other.query == query &&
      other.quantity == quantity &&
      other.portion == portion;

  @override
  int get hashCode => Object.hash(query, quantity, portion);
}

class MealDescriptionParser {
  MealDescriptionParser._();

  /// Item boundaries. Longer phrases first so " and " wins over "&" etc. Note
  /// "with"/"mit"/"con" split a dish from its sides — each becomes its own item.
  static final List<Pattern> _separators = [
    ' and ', ' with ', ' plus ', ' und ', ' mit ', ' sowie ',
    ' con ', ' y ', ' e ', ' & ', ' + ',
    RegExp(r',(?!\d)'), // comma, but not a decimal comma like "1,5"
    ';',
  ];

  /// Number words → value (en/de/es), plus articles that imply "one".
  static const Map<String, double> _numberWords = {
    'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'half': 0.5,
    'ein': 1, 'eine': 1, 'einen': 1, 'zwei': 2, 'drei': 3, 'vier': 4,
    'fünf': 5, 'sechs': 6, 'sieben': 7, 'acht': 8, 'neun': 9, 'zehn': 10,
    'halbe': 0.5, 'halb': 0.5,
    'un': 1, 'una': 1, 'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
    'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
    'medio': 0.5, 'media': 0.5,
  };

  /// Portion/unit word → normalized token.
  static const Map<String, String> _portions = {
    'g': 'g', 'gram': 'g', 'grams': 'g', 'gramm': 'g', 'gramme': 'g',
    'gramo': 'g', 'gramos': 'g',
    'kg': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogramm': 'kg',
    'kilogramo': 'kg', 'kilogramos': 'kg',
    'ml': 'ml',
    'l': 'l', 'liter': 'l', 'litre': 'l', 'liters': 'l', 'litres': 'l',
    'litro': 'l', 'litros': 'l',
    'plate': 'plate', 'plates': 'plate', 'teller': 'plate',
    'plato': 'plate', 'platos': 'plate',
    'bowl': 'bowl', 'bowls': 'bowl', 'schüssel': 'bowl', 'bol': 'bowl',
    'cuenco': 'bowl',
    'cup': 'cup', 'cups': 'cup', 'tasse': 'cup', 'tassen': 'cup',
    'taza': 'cup', 'tazas': 'cup',
    'glass': 'glass', 'glasses': 'glass', 'glas': 'glass', 'vaso': 'glass',
    'vasos': 'glass',
    'slice': 'slice', 'slices': 'slice', 'scheibe': 'slice', 'scheiben': 'slice',
    'rebanada': 'slice', 'rebanadas': 'slice',
    'handful': 'handful', 'handfuls': 'handful', 'handvoll': 'handful',
    'puñado': 'handful', 'punado': 'handful',
    'piece': 'piece', 'pieces': 'piece', 'stück': 'piece', 'stucke': 'piece',
    'pieza': 'piece', 'piezas': 'piece',
    'spoon': 'spoon', 'spoons': 'spoon', 'spoonful': 'spoon', 'löffel': 'spoon',
    'loffel': 'spoon', 'cucharada': 'spoon', 'cucharadas': 'spoon',
    'serving': 'serving', 'servings': 'serving', 'portion': 'serving',
    'portions': 'serving', 'portionen': 'serving', 'porción': 'serving',
    'porcion': 'serving', 'porciones': 'serving',
  };

  /// Words dropped from the food query (articles, connectors, "I ate" filler).
  static const Set<String> _stop = {
    'of', 'von', 'de', 'del', 'the', 'der', 'die', 'das', 'el', 'la',
    'los', 'las', 'some', 'etwas', 'algo',
    'i', 'ate', 'had', 'eat', 'eaten', 'ich', 'habe', 'hatte', 'gegessen',
    'esse', 'comi', 'comí', 'comido', 'he', 'tuve', 'tome', 'tomé',
  };

  /// Parse [input] into item suggestions (empty when nothing usable is found).
  static List<ParsedMealItem> parse(String input) {
    final text = input.trim().toLowerCase();
    if (text.isEmpty) return const [];

    final raw = _split(text)
        .map(_parseSegment)
        .whereType<_Raw>()
        .toList(growable: false);

    // A trailing "two plates" (quantity/portion, no food) applies to items that
    // lack their own quantity+portion.
    _Raw? global;
    final items = <_Raw>[];
    for (final r in raw) {
      if (r.query.isEmpty) {
        global = r;
      } else {
        items.add(r);
      }
    }
    if (items.isEmpty) return const [];

    return items.map((r) {
      var qty = r.quantity;
      String? portion = r.portion;
      if (global != null && r.quantity == 1 && r.portion == null) {
        qty = global.quantity;
        portion = global.portion;
      }
      return ParsedMealItem(query: r.query, quantity: qty, portion: portion);
    }).toList(growable: false);
  }

  static List<String> _split(String text) {
    var parts = <String>[text];
    for (final sep in _separators) {
      parts = parts.expand((p) => p.split(sep)).toList();
    }
    return parts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
  }

  /// Parse one segment into a raw item (query may be empty → global portion).
  static _Raw? _parseSegment(String seg) {
    final tokens = seg.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    double quantity = 1;
    bool foundQty = false;
    String? portion;
    final queryTokens = <String>[];

    for (final token in tokens) {
      // Strip surrounding punctuation but keep digits, letters (incl. accents)
      // and decimal separators.
      final t = token.replaceAll(RegExp(r'^[^0-9a-zäöüñ]+|[^0-9a-zäöüñ.,]+$'), '');
      if (t.isEmpty) continue;

      // "200g" / "2" / "1,5" — a number, optionally glued to a unit.
      final m = RegExp(r'^(\d+(?:[.,]\d+)?)([a-zäöüñ]*)$').firstMatch(t);
      if (m != null) {
        quantity = double.parse(m.group(1)!.replaceAll(',', '.'));
        foundQty = true;
        final suffix = m.group(2)!;
        if (suffix.isNotEmpty && _portions.containsKey(suffix)) {
          portion = _portions[suffix];
        }
        continue;
      }
      if (!foundQty && _numberWords.containsKey(t)) {
        quantity = _numberWords[t]!;
        foundQty = true;
        continue;
      }
      if (portion == null && _portions.containsKey(t)) {
        portion = _portions[t];
        continue;
      }
      if (_stop.contains(t)) continue;
      queryTokens.add(t);
    }

    // Normalize bulk units to the base the matcher understands.
    if (portion == 'kg') {
      portion = 'g';
      quantity *= 1000;
    } else if (portion == 'l') {
      portion = 'ml';
      quantity *= 1000;
    }

    final query = queryTokens.join(' ').trim();
    if (query.isEmpty && !foundQty && portion == null) return null;
    return _Raw(query: query, quantity: quantity, portion: portion);
  }
}

class _Raw {
  final String query;
  final double quantity;
  final String? portion;
  const _Raw({required this.query, required this.quantity, this.portion});
}
