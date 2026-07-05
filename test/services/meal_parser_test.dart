import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/meal_description_parser.dart';
import 'package:dietry/services/meal_parser.dart';

void main() {
  test('HeuristicMealParser delegates to MealDescriptionParser', () async {
    const parser = HeuristicMealParser();
    const input = '200g rice and two eggs';
    final got = await parser.parse(input);
    expect(got, MealDescriptionParser.parse(input));
    expect(got.length, 2);
  });
}
