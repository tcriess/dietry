import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/models/food_entry.dart';
import 'package:dietry/screens/edit_food_entry_screen.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FoodEntry entry(String unit) => FoodEntry(
      id: 'e',
      userId: 'u',
      entryDate: DateTime(2026, 10, 9),
      mealType: MealType.lunch,
      name: 'Girandole',
      amount: 125,
      unit: unit,
      calories: 200,
      protein: 7,
      fat: 1,
      carbs: 40,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> open(WidgetTester tester, FoodEntry e) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: EditFoodEntryScreen(entry: e),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a cooked weight keeps its unit', (tester) async {
    // Its per-100 values are on a cooked basis; relabelling them as raw grams
    // would silently change what was eaten.
    await open(tester, entry(kUnitGramCooked));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('g (cooked)'), findsOneWidget);
  });

  testWidgets('a plain gram entry can still switch units', (tester) async {
    await open(tester, entry(kUnitGram));

    expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
  });
}
