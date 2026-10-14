import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/main.dart';
import 'package:dietry/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// Pixel 8 in logical pixels.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('calorie stats stack instead of cutting off "Consumed"',
      (tester) async {
    phone(tester);
    final day = DateTime(2026, 10, 14);
    await tester.pumpWidget(app(Scaffold(
      body: OverviewScreen(
        goal: NutritionGoal(calories: 2182, protein: 120, fat: 70, carbs: 250),
        entries: [
          FoodEntry(
            id: 'e',
            userId: '',
            entryDate: day,
            mealType: MealType.lunch,
            name: 'Pasta',
            amount: 300,
            unit: 'g',
            calories: 1404,
            protein: 40,
            fat: 30,
            carbs: 200,
            createdAt: day,
            updatedAt: day,
          ),
        ],
        activities: [
          PhysicalActivity(
            startTime: day.add(const Duration(hours: 12)),
            endTime: day.add(const Duration(hours: 13)),
            caloriesBurned: 427,
          ),
        ],
        waterIntakeMl: 0,
        liquidFoodIntakeMl: 0,
        selectedDay: day,
        onChangeDay: (_) {},
        onJumpToToday: () {},
        canGoBack: true,
        canGoForward: false,
        onWaterChanged: (_) {},
        dbService: null,
        isCheatDay: false,
        isDayClosed: false,
        streak: 0,
        bestStreak: 0,
        onToggleCheatDay: () async {},
      ),
    )));
    await tester.pumpAndSettle();

    // Stacked rows show label and value as separate texts, in full.
    expect(find.text('Consumed:'), findsOneWidget);
    expect(find.text('1404 kcal'), findsWidgets);
    expect(find.text('Burned:'), findsOneWidget);
  });
}
