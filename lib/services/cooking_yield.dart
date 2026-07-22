import 'package:dietry/models/food_entry.dart' show EstimateLevel;
import 'package:dietry/models/food_item.dart';

/// How a food changes weight when cooked.
enum YieldKind {
  /// Absorbs water — dry goods like pasta, rice, legumes. Energy and macros are
  /// conserved, so `raw = cooked / factor` is exact.
  absorption,

  /// Loses water — most vegetables, fish. Also essentially conservative.
  evaporation,

  /// Loses water *and* fat (drip). A single weight factor is only an
  /// approximation here: pork loses ~25% weight but only ~20% energy, which is
  /// why USDA/EuroFIR pair yield factors with separate nutrient *retention*
  /// factors. We still offer the conversion, but flag it as less certain.
  fatLoss,
}

/// A cooking yield with the extra uncertainty that using a generic (rather than
/// personally measured) factor introduces.
class CookingYieldInfo {
  /// Cooked weight ÷ raw weight. >1 absorbs water, <1 loses it.
  final double factor;
  final YieldKind kind;

  /// Spread introduced by the factor itself, combined into the entry's
  /// [EstimateLevel] via `orHigher`.
  final EstimateLevel uncertainty;

  const CookingYieldInfo({
    required this.factor,
    required this.kind,
    required this.uncertainty,
  });
}

/// Match mode for a keyword. German compounds ("Vollkornnudeln") need substring
/// matching, but short keywords must not match inside unrelated words —
/// "Preiselbeere" contains "reis".
enum _Match { word, sub }

class _YieldRule {
  final List<String> keywords;
  final _Match match;
  final double factor;
  final YieldKind kind;
  final EstimateLevel uncertainty;

  const _YieldRule(
    this.keywords,
    this.match,
    this.factor,
    this.kind,
    this.uncertainty,
  );
}

/// Raw ↔ cooked weight conversion for foods whose nutrition values are declared
/// on a raw/dry basis.
///
/// Packaged foods carry per-100g values for the food **as sold** (Reg. (EU)
/// 1169/2011), but users weigh what is on the plate. For dry pasta or rice that
/// is a 2–3× error in the same direction every single time — far larger than the
/// uncertainty band we already model, and biased rather than noisy.
///
/// Factors are drawn from the USDA Table of Cooking Yields for Meat and Poultry
/// and the Bognár (FAO) weight-yield tables. They are deliberately a single
/// representative value per group: the published ranges are wide (pasta 2.0–2.5)
/// mostly because yield depends on how a given person cooks, which a generic
/// table cannot capture.
class CookingYield {
  CookingYield._();

  /// Foods that are composite dishes, canned/pre-cooked, or otherwise not a
  /// plain raw ingredient. A wrong factor is far worse than a missing option,
  /// so anything matching here is skipped entirely.
  static const List<String> _excluded = [
    // composite dishes
    'salat', 'salad', 'ensalada',
    'sauce', 'soße', 'sosse', 'salsa',
    'suppe', 'soup', 'sopa', 'eintopf',
    'auflauf', 'gratin', 'pfanne', 'curry', 'risotto',
    'fertig', 'gericht', 'menu', 'menü',
    'paniert', 'breaded', 'empanado',
    // already preserved/prepared
    'dose', 'canned', 'konserve', 'lata', 'abgetropft',
    'tiefkuhl', 'tiefkühl', 'frozen meal',
  ];

  /// Names that state the food is already on a cooked basis. Both BLS and FDC
  /// ship explicit cooked variants, and the seed data contains "Reis (gekocht)",
  /// "Kartoffel (gekocht)" and friends — converting those would divide twice.
  static const List<String> _cookedMarkers = [
    'gekocht', 'gegart', 'gebraten', 'gedunstet', 'gedünstet',
    'gegrillt', 'gebacken', 'zubereitet',
    'cooked', 'boiled', 'roasted', 'grilled', 'baked', 'steamed', 'fried',
    'cocido', 'hervido', 'asado', 'cocinado',
  ];

  static const List<_YieldRule> _rules = [
    // ---- water absorption (dry goods) ----
    _YieldRule([
      'nudel', 'pasta', 'spaghetti', 'makkaroni', 'maccheroni', 'penne',
      'fusilli', 'farfalle', 'rigatoni', 'tagliatelle', 'linguine',
      'spatzle', 'spätzle', 'fideo', 'macarron', 'macarrón',
      'espagueti', 'tallarin', 'tallarín',
    ], _Match.sub, 2.2, YieldKind.absorption, EstimateLevel.low),

    _YieldRule(['reis', 'rice', 'arroz', 'basmati', 'jasminreis'],
        _Match.word, 2.6, YieldKind.absorption, EstimateLevel.low),

    _YieldRule([
      'linsen', 'lentil', 'lenteja', 'kichererbs', 'chickpea', 'garbanzo',
      'bohnen', 'huelsenfruchte', 'hülsenfrüchte',
    ], _Match.sub, 2.5, YieldKind.absorption, EstimateLevel.low),

    _YieldRule(['bean', 'beans'],
        _Match.word, 2.5, YieldKind.absorption, EstimateLevel.low),

    _YieldRule(['couscous', 'kuskus', 'bulgur', 'quinoa', 'polenta',
        'griess', 'grieß', 'hafer'],
        _Match.sub, 2.6, YieldKind.absorption, EstimateLevel.low),

    _YieldRule(['oat', 'oats'],
        _Match.word, 2.6, YieldKind.absorption, EstimateLevel.low),

    // ---- fat + water loss (approximate; see YieldKind.fatLoss) ----
    _YieldRule(['hahnchen', 'hähnchen', 'chicken', 'pollo', 'truthahn'],
        _Match.sub, 0.73, YieldKind.fatLoss, EstimateLevel.medium),

    _YieldRule(['huhn', 'pute', 'turkey'],
        _Match.word, 0.73, YieldKind.fatLoss, EstimateLevel.medium),

    _YieldRule(['hackfleisch', 'schwein', 'cerdo', 'rindfleisch'],
        _Match.sub, 0.72, YieldKind.fatLoss, EstimateLevel.medium),

    _YieldRule(['rind', 'beef', 'hack', 'mince', 'pork', 'lamm', 'lamb'],
        _Match.word, 0.72, YieldKind.fatLoss, EstimateLevel.medium),

    // ---- water loss ----
    _YieldRule(['lachs', 'salmon', 'thunfisch', 'kabeljau', 'forelle'],
        _Match.sub, 0.82, YieldKind.evaporation, EstimateLevel.low),

    _YieldRule(['fisch', 'fish', 'pescado', 'cod'],
        _Match.word, 0.82, YieldKind.evaporation, EstimateLevel.low),

    _YieldRule(['spinat', 'spinach', 'espinaca', 'mangold'],
        _Match.sub, 0.40, YieldKind.evaporation, EstimateLevel.medium),

    _YieldRule(['champignon', 'mushroom', 'zwiebel', 'cebolla'],
        _Match.sub, 0.60, YieldKind.evaporation, EstimateLevel.medium),

    _YieldRule(['pilz', 'pilze', 'onion'],
        _Match.word, 0.60, YieldKind.evaporation, EstimateLevel.medium),

    _YieldRule(['kartoffel', 'potato', 'patata'],
        _Match.sub, 0.82, YieldKind.evaporation, EstimateLevel.low),
  ];

  /// Lowercase and fold the accents our food names actually contain, so one
  /// keyword list covers the German, English and Spanish spellings.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      buffer.write(_fold[String.fromCharCode(rune)] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static const Map<String, String> _fold = {
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'á': 'a', 'à': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  static bool _containsWord(String haystack, String word) =>
      RegExp('\\b${RegExp.escape(word)}[a-z]*\\b').hasMatch(haystack);

  static bool _matches(String haystack, _YieldRule rule) {
    for (final kw in rule.keywords) {
      final needle = normalize(kw);
      final hit = rule.match == _Match.word
          ? _containsWord(haystack, needle)
          : haystack.contains(needle);
      if (hit) return true;
    }
    return false;
  }

  /// True when the food's own name says it is already on a cooked basis, in
  /// which case no conversion must be offered.
  static bool alreadyCooked(FoodItem food) {
    final name = normalize(food.name);
    return _cookedMarkers.any((m) => name.contains(normalize(m)));
  }

  /// The default yield for [food], or null when the food has no meaningful
  /// raw→cooked distinction, is a composite dish, or is already cooked.
  static CookingYieldInfo? defaultFor(FoodItem food) {
    if (alreadyCooked(food)) return null;

    final haystack = normalize('${food.name} ${food.category ?? ''}');
    if (_excluded.any((e) => haystack.contains(normalize(e)))) return null;

    for (final rule in _rules) {
      if (_matches(haystack, rule)) {
        return CookingYieldInfo(
          factor: rule.factor,
          kind: rule.kind,
          uncertainty: rule.uncertainty,
        );
      }
    }
    return null;
  }

  /// Converts a weight measured *after* cooking back to the raw/dry weight the
  /// nutrition values are declared for.
  static double toRawGrams(double cookedGrams, double factor) =>
      factor > 0 ? cookedGrams / factor : cookedGrams;
}
