import 'package:dietry/models/food_entry.dart';
import 'package:dietry/models/tag.dart';
import 'package:dietry/services/tag_service.dart';
import 'package:flutter_test/flutter_test.dart';

const vegan = Tag(id: 't1', name: 'vegan', slug: 'vegan');
const vegetarian = Tag(id: 't2', name: 'Vegetarian', slug: 'vegetarian');
const spicy = Tag(id: 't3', name: 'spicy', slug: 'spicy');

FoodEntry entry({String? foodId, String? templateId}) {
  final now = DateTime(2026, 10, 12);
  return FoodEntry(
    id: 'e',
    userId: 'u',
    foodId: foodId,
    mealTemplateId: templateId,
    entryDate: now,
    mealType: MealType.lunch,
    name: 'x',
    amount: 100,
    unit: 'g',
    calories: 0,
    protein: 0,
    fat: 0,
    carbs: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  List<Tag> common(List<FoodEntry> entries,
          {Map<String, List<Tag>> foods = const {},
          Map<String, List<Tag>> templates = const {}}) =>
      TagService.commonTags(entries, foodTags: foods, templateTags: templates);

  test('no entries, no tags', () {
    expect(common([]), isEmpty);
  });

  test('keeps tags shared by foods and templates, sorted by name', () {
    final tags = common(
      [entry(foodId: 'f1'), entry(templateId: 'm1')],
      foods: {
        'f1': [vegetarian, vegan, spicy]
      },
      templates: {
        'm1': [vegan, vegetarian]
      },
    );
    expect(tags, [vegan, vegetarian]);
  });

  test('template tags win over the food id', () {
    final tags = common(
      [entry(foodId: 'f1', templateId: 'm1')],
      foods: {
        'f1': [spicy]
      },
      templates: {
        'm1': [vegan]
      },
    );
    expect(tags, [vegan]);
  });

  test('an untagged or unlinked entry rules out every tag', () {
    final foods = {
      'f1': [vegan]
    };
    expect(common([entry(foodId: 'f1'), entry(foodId: 'f2')], foods: foods),
        isEmpty);
    expect(common([entry(foodId: 'f1'), entry()], foods: foods), isEmpty);
  });
}
