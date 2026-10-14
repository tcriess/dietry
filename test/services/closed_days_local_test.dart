import 'dart:io';

import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/data_store.dart';
import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/models/food_entry.dart' show MealType;
import 'package:dietry/services/local_data_service.dart';
import 'package:dietry/widgets/move_copy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final local = LocalDataService.instance;

  setUpAll(() async {
    // The stub v12 DB below has none of the other tables, so DataStore's
    // loaders log errors for them; those are expected here.
    appLogger = Logger(level: Level.off);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('dietry_closed_days');
    await databaseFactory.setDatabasesPath(dir.path);

    // An install from before closed days: schema version 12, no closed_days.
    final old = await databaseFactory.openDatabase(
      p.join(dir.path, 'dietry_local.db'),
      options: OpenDatabaseOptions(version: 12, onCreate: (_, __) async {}),
    );
    await old.close();

    await local.init();
  });

  tearDownAll(() => dir.delete(recursive: true));

  final day = DateTime(2026, 10, 14);

  test('upgrade to v13 adds closed_days; close and reopen round-trip',
      () async {
    expect(await local.isDayClosed(day), isFalse);

    await local.setDayClosed(day, true);
    await local.setDayClosed(day, true); // idempotent
    expect(await local.isDayClosed(day), isTrue);
    expect(await local.isDayClosed(day.add(const Duration(days: 1))), isFalse);
    expect(await local.getAllClosedDays(), [day]);

    await local.setDayClosed(day, false);
    expect(await local.isDayClosed(day), isFalse);
    expect(await local.getAllClosedDays(), isEmpty);
  });

  test('DataStore persists the closed state per day (guest mode)', () async {
    final store = DataStore.instance..initLocal(local);

    await store.loadDay(day);
    expect(store.isDayClosed, isFalse);

    await store.setDayClosed(day, true);
    expect(store.isDayClosed, isTrue);

    await store.loadDay(day.subtract(const Duration(days: 1)));
    expect(store.isDayClosed, isFalse);

    await store.loadDay(day);
    expect(store.isDayClosed, isTrue);
  });

  test('isClosedOn answers for a day other than the one on screen', () async {
    final store = DataStore.instance..initLocal(local);
    final other = day.add(const Duration(days: 3));
    await store.loadDay(day);

    expect(await store.isClosedOn(other), isFalse);
    await local.setDayClosed(other, true);
    expect(await store.isClosedOn(other), isTrue);
    await local.setDayClosed(other, false);
  });

  testWidgets('move/copy sheet refuses a closed target day', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final store = DataStore.instance..initLocal(local);
    await tester.runAsync(() async {
      await store.loadDay(today.subtract(const Duration(days: 5)));
      await local.setDayClosed(today, true);
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showMoveCopySheet(context,
                title: 'Apple', initialMeal: MealType.lunch),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> settleLookup() async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }

    ButtonStyleButton button(String label) => tester.widget<ButtonStyleButton>(
        find.ancestor(
            of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));

    // Starts on today, which is closed.
    await settleLookup();
    expect(find.text('This day is closed.'), findsOneWidget);
    expect(button('Move').onPressed, isNull);
    expect(button('Copy').onPressed, isNull);

    await tester.tap(find.text('Yesterday'));
    await settleLookup();
    expect(find.text('This day is closed.'), findsNothing);
    expect(button('Move').onPressed, isNotNull);
    expect(button('Copy').onPressed, isNotNull);

    await tester.runAsync(() => local.setDayClosed(today, false));
  });
}
