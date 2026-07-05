import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/meal_description_parser.dart';

void main() {
  group('MealDescriptionParser', () {
    List<ParsedMealItem> parse(String s) => MealDescriptionParser.parse(s);

    test('empty / whitespace → no items', () {
      expect(parse(''), isEmpty);
      expect(parse('   '), isEmpty);
    });

    test('single bare food', () {
      expect(parse('banana'), [const ParsedMealItem(query: 'banana')]);
    });

    test('weighed grams glued to number', () {
      expect(parse('200g rice'),
          [const ParsedMealItem(query: 'rice', quantity: 200, portion: 'g')]);
    });

    test('weighed grams as separate token', () {
      expect(parse('150 g chicken'),
          [const ParsedMealItem(query: 'chicken', quantity: 150, portion: 'g')]);
    });

    test('bare count', () {
      expect(parse('two eggs'),
          [const ParsedMealItem(query: 'eggs', quantity: 2)]);
    });

    test('article + named portion + connector', () {
      expect(parse('a slice of bread'),
          [const ParsedMealItem(query: 'bread', quantity: 1, portion: 'slice')]);
    });

    test('splits on "with" and "and" into separate items', () {
      final r = parse('rice with paprika and peas');
      expect(r.map((e) => e.query), ['rice', 'paprika', 'peas']);
    });

    test('trailing global portion applies to portion-less items', () {
      final r = parse('rice with paprika and peas, two plates');
      expect(r.length, 3);
      expect(r.every((e) => e.quantity == 2 && e.portion == 'plate'), isTrue);
      expect(r.map((e) => e.query), ['rice', 'paprika', 'peas']);
    });

    test('per-item quantity is not overridden by a global', () {
      final r = parse('200g rice and peas, two plates');
      // rice already has its own g quantity → keep it; peas takes the global.
      expect(r[0],
          const ParsedMealItem(query: 'rice', quantity: 200, portion: 'g'));
      expect(r[1],
          const ParsedMealItem(query: 'peas', quantity: 2, portion: 'plate'));
    });

    test('strips "I ate" filler', () {
      final r = parse('I ate grilled chicken and rice');
      expect(r.map((e) => e.query), ['grilled chicken', 'rice']);
    });

    test('kg is normalized to grams', () {
      expect(parse('1 kg potatoes'),
          [const ParsedMealItem(query: 'potatoes', quantity: 1000, portion: 'g')]);
    });

    test('liters normalized to ml', () {
      expect(parse('half l milk'),
          [const ParsedMealItem(query: 'milk', quantity: 500, portion: 'ml')]);
    });

    test('decimal with comma', () {
      expect(parse('1,5 cups oats'),
          [const ParsedMealItem(query: 'oats', quantity: 1.5, portion: 'cup')]);
    });

    test('German: portion + food, split on "mit"', () {
      final r = parse('zwei Teller Reis mit Paprika');
      expect(r[0],
          const ParsedMealItem(query: 'reis', quantity: 2, portion: 'plate'));
      expect(r[1], const ParsedMealItem(query: 'paprika'));
    });

    test('Spanish: split on "con" and "y"', () {
      final r = parse('arroz con pimiento y guisantes');
      expect(r.map((e) => e.query), ['arroz', 'pimiento', 'guisantes']);
      expect(r.every((e) => e.quantity == 1 && e.portion == null), isTrue);
    });

    test('Spanish quantity + portion', () {
      expect(parse('dos vasos de leche'),
          [const ParsedMealItem(query: 'leche', quantity: 2, portion: 'glass')]);
    });
  });
}
