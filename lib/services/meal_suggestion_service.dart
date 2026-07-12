import 'package:uuid/uuid.dart';

import '../models/food_entry.dart';
import '../models/food_item.dart';
import 'app_logger.dart';
import 'food_database_service.dart';
import 'meal_description_parser.dart';
import 'meal_parser.dart';

/// One suggestion: a parsed item, its best fuzzy food match (or none), and the
/// grams that match resolves to. The UI shows these for review before logging.
class MealItemSuggestion {
  final ParsedMealItem parsed;

  /// Best fuzzy hit from the food DB, or null when nothing matched.
  final FoodItem? match;

  /// Grams the parsed quantity/portion resolves to against [match] (0 if none).
  final double grams;

  /// The term that actually produced [match], when the food as typed found
  /// nothing and an LLM-suggested alias did ("gaspaccho" → "cold tomato soup").
  /// Null for a direct hit. The UI surfaces this — a silent substitution would
  /// be a lie about what the user ate.
  final String? matchedVia;

  const MealItemSuggestion({
    required this.parsed,
    this.match,
    this.grams = 0,
    this.matchedVia,
  });

  bool get matched => match != null;

  /// True when [match] is a stand-in rather than the food as typed.
  bool get isSubstitute => matchedVia != null;

  /// A described meal is a rough estimate: a stated weight is only *medium*
  /// sure, a vague portion or bare count is *high*.
  ///
  /// A substitution is uncertain about *what* was eaten, not merely how much, so
  /// it is never better than [EstimateLevel.high] however precisely the amount
  /// was stated. (Levels combine by taking the max — see [EstimateLevel.orHigher].)
  EstimateLevel get estimateLevel {
    final fromPortion = (parsed.portion == 'g' || parsed.portion == 'ml')
        ? EstimateLevel.medium
        : EstimateLevel.high;
    return isSubstitute ? fromPortion.orHigher(EstimateLevel.high) : fromPortion;
  }

  /// Build a draft log entry (grams-based, so nutrition is exact-per-gram) for
  /// the matched food. Returns null when there is no match. Caller confirms it.
  FoodEntry? toFoodEntry({
    required String userId,
    required DateTime date,
    required MealType mealType,
    double? gramsOverride,
  }) {
    final food = match;
    final g = gramsOverride ?? grams;
    if (food == null || g <= 0) return null;
    final f = g / 100.0;
    final now = DateTime.now();
    return FoodEntry(
      id: const Uuid().v4(),
      userId: userId,
      foodId: food.id.isEmpty ? null : food.id,
      entryDate: date,
      mealType: mealType,
      name: food.name,
      amount: g,
      unit: food.isLiquid ? 'ml' : 'g',
      calories: food.calories * f,
      protein: food.protein * f,
      fat: food.fat * f,
      carbs: food.carbs * f,
      fiber: food.fiber != null ? food.fiber! * f : null,
      sugar: food.sugar != null ? food.sugar! * f : null,
      sodium: food.sodium != null ? food.sodium! * f : null,
      saturatedFat: food.saturatedFat != null ? food.saturatedFat! * f : null,
      isLiquid: food.isLiquid,
      amountMl: food.isLiquid ? g : null,
      estimateLevel: estimateLevel,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Given a food name the database could not match, produce alternative search
/// terms to try (other names for the dish, then its main ingredients).
/// Implemented by the on-device LLM; injected so this service stays testable and
/// works unchanged when there is no model.
typedef AliasResolver = Future<List<String>> Function(String foodName);

/// Ties the offline [MealDescriptionParser] to the food DB: parse a description,
/// fuzzy-match each item, and resolve a gram amount for each.
class MealSuggestionService {
  final FoodDatabaseService _foods;

  /// How the description is parsed into items. Defaults to the offline
  /// heuristic; an on-device LLM parser (Pro/mobile) is injected here later.
  final MealParser _parser;

  /// Optional second chance for items the database could not match. Null (the
  /// default, and always the case without an on-device model) simply means an
  /// unmatched item stays unmatched, exactly as before.
  final AliasResolver? _resolveAliases;

  MealSuggestionService(
    this._foods, {
    MealParser parser = const HeuristicMealParser(),
    AliasResolver? aliasResolver,
  })  : _parser = parser,
        _resolveAliases = aliasResolver;

  /// Rough average grams per named portion — only a starting point; the whole
  /// entry is tagged uncertain and the user edits before logging.
  static const Map<String, double> _defaultPortionGrams = {
    'plate': 350,
    'bowl': 300,
    'cup': 150,
    'glass': 250,
    'slice': 30,
    'handful': 30,
    'piece': 60,
    'spoon': 15,
    'serving': 100,
  };

  Future<List<MealItemSuggestion>> suggest(String description) async {
    final items = await _parser.parse(description);
    final out = <MealItemSuggestion>[];
    for (final item in items) {
      var match = await _bestMatch(item.query);
      String? via;

      // Nothing found. The food search matches spelling, not meaning, so it can
      // never get from "gaspaccho" to a tomato soup (word_similarity 0.357 — far
      // below any threshold that does not also flood the results with junk). Ask
      // the model what the food *is* and search for that instead.
      if (match == null && _resolveAliases != null) {
        for (final alias in await _aliasesFor(item.query)) {
          final hit = await _bestMatch(alias);
          if (hit != null) {
            match = hit;
            via = alias;
            break;
          }
        }
      }

      out.add(MealItemSuggestion(
        parsed: item,
        match: match,
        matchedVia: via,
        grams: match == null ? 0 : resolveGrams(item, match),
      ));
    }
    return out;
  }

  Future<FoodItem?> _bestMatch(String query) async {
    final results = await _foods.searchFoods(query, limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Never throws: a failed alias lookup (model error, timeout, garbage output)
  /// just means the item stays unmatched, which is where it already was.
  Future<List<String>> _aliasesFor(String query) async {
    try {
      return await _resolveAliases!(query);
    } catch (e) {
      appLogger.w('⚠️ Alias lookup failed for "$query" → leaving unmatched: $e');
      return const [];
    }
  }

  /// Resolve a parsed quantity/portion to grams against a matched food.
  static double resolveGrams(ParsedMealItem item, FoodItem food) {
    final q = item.quantity;
    final p = item.portion;
    if (p == 'g' || p == 'ml') return q; // weighed directly
    // Bare count or a generic "serving" → the food's own primary portion if it
    // defines one, else its serving size, else 100 g.
    if (p == null || p == 'serving') {
      final base = food.portions.isNotEmpty
          ? food.portions.first.amountG
          : (food.servingSize ?? 100.0);
      return q * base;
    }
    // Named portion → rough average grams.
    return q * (_defaultPortionGrams[p] ?? food.servingSize ?? 100.0);
  }
}
