import 'meal_description_parser.dart';

/// Turns a free-text meal description into rough item suggestions
/// ([ParsedMealItem]s). Two implementations feed the same
/// `MealSuggestionService` matcher downstream:
///   - [HeuristicMealParser] — offline, rule-based, always available (CE + the
///     free tier, and the fallback);
///   - an on-device LLM parser (Pro + mobile, added in phase 3b/3c) that plugs
///     in here without touching the matcher, review UI, or voice input.
abstract class MealParser {
  Future<List<ParsedMealItem>> parse(String text);
}

/// The offline heuristic parser — the default and the fallback.
class HeuristicMealParser implements MealParser {
  const HeuristicMealParser();

  @override
  Future<List<ParsedMealItem>> parse(String text) async =>
      MealDescriptionParser.parse(text);
}
