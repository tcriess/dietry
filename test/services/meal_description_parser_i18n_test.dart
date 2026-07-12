import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/meal_description_parser.dart';

/// A portion word that survives into the query string guarantees a "No match":
/// the food search looks for *"schale gaspacho"*, which no food is called. The
/// English vocabulary stripped these; the German one had holes, so common German
/// portion words silently broke describe-meal for the app's primary language.
void main() {
  ParsedMealItem only(String input) {
    final items = MealDescriptionParser.parse(input);
    expect(items, hasLength(1), reason: 'expected one item from "$input"');
    return items.single;
  }

  group('German portion words are stripped from the query', () {
    test('Schale / Schalen (was missing entirely — only Schüssel was listed)', () {
      expect(only('eine Schale Gaspacho').query, 'gaspacho');
      expect(only('eine Schale Gaspacho').portion, 'bowl');
      expect(only('2 Schalen Suppe').quantity, 2);
      expect(only('2 Schalen Suppe').query, 'suppe');
    });

    test('Schüssel and its plural', () {
      expect(only('1 Schüssel Reis').query, 'reis');
      expect(only('1 Schüssel Reis').portion, 'bowl');
      expect(only('2 Schüsseln Reis').query, 'reis');
    });

    test('plural Stücke (only the singular Stück was listed)', () {
      final r = only('2 Stücke Brot');
      expect(r.query, 'brot');
      expect(r.portion, 'piece');
      expect(r.quantity, 2);
    });

    test('plural Gläser (only the singular Glas was listed)', () {
      final r = only('2 Gläser Milch');
      expect(r.query, 'milch');
      expect(r.portion, 'glass');
      expect(r.quantity, 2);
    });

    test('Becher, Esslöffel, Teelöffel', () {
      expect(only('1 Becher Joghurt').portion, 'cup');
      expect(only('2 Esslöffel Olivenöl').portion, 'spoon');
      expect(only('1 Teelöffel Zucker').portion, 'spoon');
    });
  });

  group('umlaut folding — typed with or without the umlaut', () {
    test('portion words', () {
      expect(only('2 Stucke Brot').portion, 'piece'); // no umlaut
      expect(only('2 Stücke Brot').portion, 'piece'); // umlaut
      expect(only('1 Schussel Reis').portion, 'bowl');
      expect(only('1 Schüssel Reis').portion, 'bowl');
    });

    test('number words', () {
      expect(only('fünf Äpfel').quantity, 5);
      expect(only('funf Äpfel').quantity, 5); // 'fünf' was listed, 'funf' was not
    });

    test('the food name keeps its original spelling', () {
      // Folding is for vocabulary lookup only — the query must not be mangled,
      // and the database search unaccents on its own side anyway.
      expect(only('2 Stücke Käse').query, 'käse');
      expect(only('1 Glas Öl').query, 'öl');
    });
  });

  group('English and Spanish still work', () {
    test('English', () {
      expect(only('a bowl of tomato soup').query, 'tomato soup');
      expect(only('a bowl of tomato soup').portion, 'bowl');
      expect(only('2 tablespoons olive oil').portion, 'spoon');
    });

    test('Spanish', () {
      expect(only('un cuenco de sopa').query, 'sopa');
      expect(only('un cuenco de sopa').portion, 'bowl');
      expect(only('2 vasos de leche').portion, 'glass');
    });

    test("'el' stays a Spanish article, not an Esslöffel abbreviation", () {
      // Portions are matched before stop words, so adding 'el' as shorthand for
      // Esslöffel would eat the article out of every Spanish phrase.
      final r = only('el pollo');
      expect(r.query, 'pollo');
      expect(r.portion, isNull);
    });
  });

  group('the field report: "1 bowl of gaspaccho"', () {
    test('the typo reaches the search intact, portion stripped', () {
      final r = only('1 bowl of gaspaccho');
      expect(r.query, 'gaspaccho'); // search_food_database resolves this to "Gaspacho"
      expect(r.portion, 'bowl');
    });

    test('and so does the German phrasing', () {
      expect(only('eine Schale Gaspaccho').query, 'gaspaccho');
    });
  });
}
