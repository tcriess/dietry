import 'package:uuid/uuid.dart';

import '../models/food_entry.dart';
import '../models/food_item.dart';
import 'food_database_service.dart';
import 'meal_description_parser.dart';

/// One suggestion: a parsed item, its best fuzzy food match (or none), and the
/// grams that match resolves to. The UI shows these for review before logging.
class MealItemSuggestion {
  final ParsedMealItem parsed;

  /// Best fuzzy hit from the food DB, or null when nothing matched.
  final FoodItem? match;

  /// Grams the parsed quantity/portion resolves to against [match] (0 if none).
  final double grams;

  const MealItemSuggestion({
    required this.parsed,
    this.match,
    this.grams = 0,
  });

  bool get matched => match != null;

  /// A described meal is a rough estimate: a stated weight is only *medium*
  /// sure, a vague portion or bare count is *high*.
  EstimateLevel get estimateLevel =>
      (parsed.portion == 'g' || parsed.portion == 'ml')
          ? EstimateLevel.medium
          : EstimateLevel.high;

  /// Build a draft log entry (grams-based, so nutrition is exact-per-gram) for
  /// the matched food. Returns null when there is no match. Caller confirms it.
  FoodEntry? toFoodEntry({
    required String userId,
    required DateTime date,
    required MealType mealType,
  }) {
    final food = match;
    if (food == null || grams <= 0) return null;
    final f = grams / 100.0;
    final now = DateTime.now();
    return FoodEntry(
      id: const Uuid().v4(),
      userId: userId,
      foodId: food.id.isEmpty ? null : food.id,
      entryDate: date,
      mealType: mealType,
      name: food.name,
      amount: grams,
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
      amountMl: food.isLiquid ? grams : null,
      estimateLevel: estimateLevel,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Ties the offline [MealDescriptionParser] to the food DB: parse a description,
/// fuzzy-match each item, and resolve a gram amount for each.
class MealSuggestionService {
  final FoodDatabaseService _foods;
  MealSuggestionService(this._foods);

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
    final items = MealDescriptionParser.parse(description);
    final out = <MealItemSuggestion>[];
    for (final item in items) {
      final results = await _foods.searchFoods(item.query, limit: 1);
      final match = results.isNotEmpty ? results.first : null;
      out.add(MealItemSuggestion(
        parsed: item,
        match: match,
        grams: match == null ? 0 : resolveGrams(item, match),
      ));
    }
    return out;
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
