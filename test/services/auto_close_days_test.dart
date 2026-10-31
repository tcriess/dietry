import 'dart:io';

import 'package:dietry/models/food_entry.dart';
import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/auto_close_days.dart';
import 'package:dietry/services/data_store.dart';
import 'package:dietry/services/local_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => appLogger = Logger(level: Level.off));

  // A Wednesday afternoon: Tuesday is in its grace day, Monday is due.
  final now = DateTime(2026, 10, 28, 15, 30);
  final mon = DateTime(2026, 10, 26);
  final tue = DateTime(2026, 10, 27);

  group('window', () {
    test('first run reaches back a week, up to the day before yesterday', () {
      final w = AutoCloseDays.window(now, null)!;
      expect(w.to, mon);
      expect(w.from, DateTime(2026, 10, 20));
    });

    test('continues after the stored progress', () {
      final w = AutoCloseDays.window(now, DateTime(2026, 10, 24))!;
      expect(w.from, DateTime(2026, 10, 25));
      expect(w.to, mon);
    });

    test('nothing is due when the progress is current', () {
      expect(AutoCloseDays.window(now, mon), isNull);
      // Late in the evening it is still the same day.
      expect(AutoCloseDays.window(DateTime(2026, 10, 28, 23, 59), mon), isNull);
    });

    test('yesterday comes due at midnight', () {
      final w = AutoCloseDays.window(DateTime(2026, 10, 29, 0, 1), mon)!;
      expect(w.from, tue);
      expect(w.to, tue);
    });
  });

  group('run', () {
    late List<DateTime> closed;
    late Set<DateTime> withEntries;

    Future<int> run({Object? fail}) => AutoCloseDays.run(
          'u1',
          now: now,
          findDays: (from, to) async {
            if (fail != null) throw fail;
            return withEntries
                .where((d) => !d.isBefore(from) && !d.isAfter(to))
                .toSet();
          },
          closeDays: (days) async => closed.addAll(days),
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      closed = [];
      withEntries = {DateTime(2026, 10, 10), DateTime(2026, 10, 22), mon, tue};
    });

    test('closes only due days with entries inside the lookback', () async {
      expect(await run(), 2);
      expect(closed, [DateTime(2026, 10, 22), mon]);
    });

    test('a second run the same day does nothing, so reopened days stay open',
        () async {
      await run();
      closed.clear();
      expect(await run(), 0);
      expect(closed, isEmpty);
    });

    test('a failed lookup keeps the progress and is retried', () async {
      expect(await run(fail: Exception('offline')), 0);
      expect(await run(), 2);
    });

    test('does nothing while disabled; re-enabling starts over', () async {
      await run();
      await AutoCloseDays.setEnabled(false);
      closed.clear();
      expect(await run(), 0);

      await AutoCloseDays.setEnabled(true);
      expect(await run(), 2); // the progress was forgotten
    });

    test('is on by default', () async {
      expect(await AutoCloseDays.isEnabled(), isTrue);
    });
  });

  group('guest store', () {
    late Directory dir;
    final local = LocalDataService.instance;
    final store = DataStore.instance;

    FoodEntry entry(String id, DateTime day) => FoodEntry(
          id: id,
          userId: 'guest',
          entryDate: day,
          mealType: MealType.lunch,
          name: id,
          amount: 1,
          unit: 'g',
          calories: 1,
          protein: 0,
          fat: 0,
          carbs: 0,
          createdAt: day,
          updatedAt: day,
        );

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('dietry_auto_close');
      await databaseFactory.setDatabasesPath(dir.path);
      await local.init();
      store.initLocal(local);
      await local.createFoodEntry(entry('a', mon));
      await local.createFoodEntry(entry('b', mon));
      await local.createFoodEntry(entry('c', DateTime(2026, 10, 30)));
    });

    tearDownAll(() => dir.delete(recursive: true));

    test('lists each day with entries once', () async {
      expect(await store.foodEntryDatesInRange(DateTime(2026, 10, 20), tue),
          {mon});
    });

    test('closeDays leaves the day on screen alone unless it is one of them',
        () async {
      await store.loadDay(tue);
      await store.closeDays([mon]);
      expect(await local.isDayClosed(mon), isTrue);
      expect(store.isDayClosed, isFalse);

      await store.closeDays([tue]);
      expect(store.isDayClosed, isTrue);
    });
  });
}
