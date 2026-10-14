import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/services/app_logger.dart';
import 'package:dietry/screens/add_food_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

Widget app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() => appLogger = Logger(level: Level.off));

  testWidgets('manual entry refuses an empty name scrolled out of view',
      (tester) async {
    // Short enough that the name field scrolls away; wide enough for the
    // test font, whose glyphs are full squares.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const AddFoodEntryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    // Scroll to the bottom, the way you would to reach the nutrition fields.
    await tester.drag(
        find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.byType(AddFoodEntryScreen), findsOneWidget);
  });
}
