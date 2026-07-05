import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/ai_meal_parser.dart';
import 'package:dietry/services/meal_description_parser.dart';

void main() {
  group('AiMealParser.parseResponse', () {
    test('clean JSON array', () {
      final r = AiMealParser.parseResponse(
          '[{"food":"rice","quantity":2,"unit":"plate"},{"food":"milk","quantity":250,"unit":"ml"}]');
      expect(r, [
        const ParsedMealItem(query: 'rice', quantity: 2, portion: 'plate'),
        const ParsedMealItem(query: 'milk', quantity: 250, portion: 'ml'),
      ]);
    });

    test('tolerates code fences and prose around the array', () {
      final r = AiMealParser.parseResponse(
          'Sure! Here you go:\n```json\n[{"food":"eggs","quantity":2,"unit":null}]\n```\nHope that helps.');
      expect(r, [const ParsedMealItem(query: 'eggs', quantity: 2)]);
    });

    test('unknown unit becomes null; name key and string qty accepted', () {
      final r = AiMealParser.parseResponse(
          '[{"name":"bread","quantity":"1.5","unit":"loaf"}]');
      expect(r, [const ParsedMealItem(query: 'bread', quantity: 1.5)]);
    });

    test('skips malformed elements but keeps valid ones', () {
      final r = AiMealParser.parseResponse(
          '[{"food":""},{"nope":1},{"food":"oats","quantity":0,"unit":"cup"}]');
      // empty + junk skipped; qty<=0 coerced to 1.
      expect(r, [const ParsedMealItem(query: 'oats', quantity: 1, portion: 'cup')]);
    });

    test('strips a <think> reasoning block before the JSON', () {
      final r = AiMealParser.parseResponse(
          '<think>Okay, the user said rice. Let me [reason] about units...</think>\n'
          '[{"food":"rice","quantity":2,"unit":"plate"}]');
      expect(r,
          [const ParsedMealItem(query: 'rice', quantity: 2, portion: 'plate')]);
    });

    test('throws when no array present', () {
      expect(() => AiMealParser.parseResponse('I could not understand that.'),
          throwsFormatException);
    });

    test('throws when array has no usable items', () {
      expect(() => AiMealParser.parseResponse('[{"x":1},{}]'),
          throwsFormatException);
    });
  });

  group('AiMealParser.parse (via injected generate)', () {
    test('builds prompt and parses the generated JSON', () async {
      String? seenPrompt;
      final parser = AiMealParser((prompt) async {
        seenPrompt = prompt;
        return '[{"food":"rice","quantity":1,"unit":null}]';
      });
      final r = await parser.parse('some rice');
      expect(seenPrompt, contains('some rice'));
      expect(r, [const ParsedMealItem(query: 'rice')]);
    });
  });
}
