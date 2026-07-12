import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/food_entry.dart';
import 'package:dietry/services/ai_meal_parser.dart';

/// The alias fallback exists because the food search matches SPELLING, not
/// MEANING. Measured against the production database:
///
///   word_similarity('gaspaccho', 'gazpacho') = 0.357
///
/// which is below the 0.6 threshold in force and below even the 0.4 the search
/// was designed for — and at 0.4 the typo matches "GARI", not gazpacho. No
/// trigram tuning reaches it. The model, however, knows what gazpacho is.
void main() {
  group('AiMealParser.buildAliasPrompt', () {
    test('asks for dish names before ingredients, and quotes the food safely', () {
      final p = AiMealParser.buildAliasPrompt('gaspaccho');
      expect(p, contains('"gaspaccho"'));
      expect(p, contains('JSON array of')); // the phrase wraps a line in the source
      // Order matters: a different name for the same dish is a far better log
      // entry than a pile of raw ingredients.
      expect(p.indexOf('other common names'),
          lessThan(p.indexOf('then its main ingredients')));
    });

    test('a quote in the food name cannot break out of the prompt', () {
      expect(AiMealParser.buildAliasPrompt('the "best" soup'), isNot(contains('"best"')));
    });
  });

  group('AiMealParser.parseAliases', () {
    test('extracts terms from a clean array', () {
      final r = AiMealParser.parseAliases(
        '["cold tomato soup","tomato soup","tomato","cucumber"]',
        original: 'gaspaccho',
      );
      expect(r, ['cold tomato soup', 'tomato soup', 'tomato', 'cucumber']);
    });

    test('tolerates prose and code fences around the array', () {
      final r = AiMealParser.parseAliases(
        'Sure! Here you go:\n```json\n["tomato soup","tomato"]\n```\nHope that helps.',
        original: 'gaspaccho',
      );
      expect(r, ['tomato soup', 'tomato']);
    });

    test('cleans a portion word out of a term the model wrapped in prose', () {
      // A weak model answers "a bowl of tomato soup"; the searchable term is
      // "tomato soup" — "bowl" is in no food name and guarantees a miss.
      final r = AiMealParser.parseAliases(
        '["a bowl of tomato soup"]',
        original: 'gaspaccho',
      );
      expect(r, ['tomato soup']);
    });

    test('drops the original term — re-searching it is a wasted round trip', () {
      final r = AiMealParser.parseAliases(
        '["Gaspaccho","tomato soup"]',
        original: 'gaspaccho',
      );
      expect(r, ['tomato soup']);
    });

    test('de-dupes and caps at maxAliases', () {
      final r = AiMealParser.parseAliases(
        '["a","a","b","c","d","e","f","g"]',
        original: 'x',
      );
      expect(r.length, AiMealParser.maxAliases);
      expect(r, ['a', 'b', 'c', 'd', 'e']);
    });

    test('returns empty rather than throwing on garbage', () {
      // An unusable alias lookup is not an error — the item just stays unmatched.
      expect(AiMealParser.parseAliases('I do not know.', original: 'x'), isEmpty);
      expect(AiMealParser.parseAliases('[not json]', original: 'x'), isEmpty);
      expect(AiMealParser.parseAliases('[1, 2, 3]', original: 'x'), isEmpty);
      expect(AiMealParser.parseAliases('', original: 'x'), isEmpty);
    });

    test('bails on output truncated mid-reasoning', () {
      expect(
        AiMealParser.parseAliases('<think>hmm ["tomato"', original: 'x'),
        isEmpty,
      );
    });

    test('reads only the answer after a closed reasoning block', () {
      expect(
        AiMealParser.parseAliases(
          '<think>maybe ["wrong"]</think>["tomato soup"]',
          original: 'x',
        ),
        ['tomato soup'],
      );
    });
  });

  group('resolveAliases (via an injected generator)', () {
    test('round-trips prompt → generation → terms', () async {
      late String seenPrompt;
      final parser = AiMealParser((p) async {
        seenPrompt = p;
        return '["cold tomato soup","tomato"]';
      });
      final aliases = await parser.resolveAliases('gaspaccho');
      expect(seenPrompt, contains('gaspaccho'));
      expect(aliases, ['cold tomato soup', 'tomato']);
    });

    test('a wedged model does not hang forever', () {
      // There used to be no timeout anywhere in the chain: a stalled generation
      // left the review screen spinning indefinitely.
      expect(AiMealParser.generateTimeout, lessThanOrEqualTo(const Duration(minutes: 1)));
    });
  });

  group('a substitution is a rougher estimate than a direct hit', () {
    test('EstimateLevel ordering is what this relies on', () {
      // none < low < medium < high, where higher = rougher. A substitution is a
      // guess about WHAT was eaten, not merely how much, so it can never be
      // better than `high` however precisely the amount was stated.
      expect(EstimateLevel.high.index, greaterThan(EstimateLevel.medium.index));
      expect(
        EstimateLevel.medium.orHigher(EstimateLevel.high),
        EstimateLevel.high,
      );
    });
  });
}
