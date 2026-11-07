import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/models/food_entry.dart';
import 'package:dietry/models/food_item.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/services/neon_database_service.dart';
import 'package:dietry/widgets/quick_food_entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the confirm dialog on a phone-sized screen with the keyboard up.
Future<void> openDialog(WidgetTester tester, Locale locale) async {
  // Pixel 8 (411x914 dp) with a ~330 dp keyboard.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2.625);
  addTearDown(tester.view.reset);

  final now = DateTime(2026);
  // Oats: a raw/dry food, so the cooked-weight nudge shows too.
  final food = FoodItem(
      id: 'f1',
      name: 'Haferflocken kernig',
      calories: 372,
      protein: 13.5,
      fat: 7,
      carbs: 58.7,
      isPublic: true,
      isApproved: true,
      brand: 'Kölln',
      category: 'Getreide',
      source: 'OpenFoodFacts',
      portions: const [FoodPortion(name: '1 Esslöffel', amountG: 10)],
      createdAt: now,
      updatedAt: now);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showDialog(
            context: ctx,
            builder: (_) => debugConfirmDialog(
                name: food.name,
                mealType: MealType.lunch,
                food: food,
                dbService: NeonDatabaseService()),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets(
        'confirm dialog fits above the keyboard without covering the meal '
        'picker ($locale)', (tester) async {
      await openDialog(tester, locale);
      expect(tester.takeException(), isNull);

      final keyboardTop = 914.3 - 330;
      final mealFinder = find.byType(DropdownButton<MealType>);
      final meal = tester.getRect(mealFinder);
      final sure = tester.getRect(find.byType(DropdownButton<EstimateLevel>));
      // Meal and "how sure?" share one row.
      expect(sure.top, closeTo(meal.top, 1));

      // The actions stay above the keyboard.
      for (final button in [find.byType(FilledButton), find.byType(TextButton)]) {
        expect(tester.getRect(button.last).bottom,
            lessThanOrEqualTo(keyboardTop));
      }

      // The meal picker is reachable and not covered: tapping it opens the
      // menu (a covered picker would swallow the tap in an action button).
      await tester.ensureVisible(mealFinder);
      await tester.pumpAndSettle();
      await tester.tap(mealFinder, warnIfMissed: false);
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.textContaining(MealType.dinner.localizedName(l)),
          findsWidgets);
    });
  }
}
