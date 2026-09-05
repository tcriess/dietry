import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/models/food_entry.dart';
import 'package:dietry/utils/unit_utils.dart';
import 'package:dietry/widgets/quick_estimate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a host screen whose only button opens the sheet, and hands back a
/// getter for whatever it returned.
Future<QuickEstimate? Function()> openSheet(WidgetTester tester,
    {String? initialName}) async {
  // Tall enough that the whole sheet is laid out at once — the fields and the
  // Add button then need no scrolling, and lazily-built rows all exist.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  QuickEstimate? result;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result =
                await showQuickEstimateSheet(ctx, initialName: initialName);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), value);
  await tester.pump();
}

Future<void> tapAdd(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('totals without a weight come back as one portion',
      (tester) async {
    final result = await openSheet(tester);

    await fill(tester, 'Name', 'Canteen plate');
    await fill(tester, 'Calories', '450');
    await fill(tester, 'Protein', '25');
    await tapAdd(tester);

    final e = result()!;
    expect(e.name, 'Canteen plate');
    expect(e.calories, 450);
    expect(e.protein, 25);
    expect(e.isMeal, isTrue);
    expect(e.unit, kUnitPortion);
    expect(e.amount, 1);
  });

  testWidgets('per-100 values are scaled by the weight', (tester) async {
    final result = await openSheet(tester);

    await fill(tester, 'Name', 'Rice');
    await tester.tap(find.text('Per 100'));
    await tester.pumpAndSettle();
    await fill(tester, 'Amount', '250');
    await fill(tester, 'Calories', '130');
    await tapAdd(tester);

    final e = result()!;
    expect(e.calories, closeTo(325, 1e-9));
    expect(e.amount, 250);
    expect(e.unit, kUnitGram);
    expect(e.isMeal, isFalse);
    expect(e.amountG, 250);
  });

  testWidgets('per-100 mode refuses to submit without a weight',
      (tester) async {
    final result = await openSheet(tester);

    await fill(tester, 'Name', 'Rice');
    await tester.tap(find.text('Per 100'));
    await tester.pumpAndSettle();
    await fill(tester, 'Calories', '130');
    await tapAdd(tester);

    expect(result(), isNull, reason: 'the sheet stays open');
    expect(find.text('Please enter an amount'), findsOneWidget);
  });

  testWidgets('a name alone is not enough to log something', (tester) async {
    final result = await openSheet(tester);

    await fill(tester, 'Name', 'Something');
    await tapAdd(tester);

    expect(result(), isNull);
    expect(find.text('Enter at least one nutrition value'), findsOneWidget);
  });

  testWidgets('a calorie-free drink logs on its volume alone', (tester) async {
    final result = await openSheet(tester);

    await fill(tester, 'Name', 'Sparkling water');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ml').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Weight (optional)', '500');
    await tapAdd(tester);

    final e = result()!;
    expect(e.calories, 0);
    expect(e.isLiquid, isTrue);
    expect(e.amountMl, 500);
  });

  testWidgets('a search query is carried in as the name', (tester) async {
    final result = await openSheet(tester, initialName: 'Omas Streuselkuchen');

    await fill(tester, 'Calories', '380');
    await tapAdd(tester);

    expect(result()!.name, 'Omas Streuselkuchen');
    expect(result()!.estimateLevel, EstimateLevel.medium,
        reason: 'a quick estimate defaults to "rough"');
  });
}
