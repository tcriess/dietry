import 'package:dietry/models/food_entry.dart';
import 'package:dietry/services/data_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The food log's display order.
///
/// The list screen groups by meal type and renders in list order without
/// sorting of its own, so whatever order DataStore holds is what the user sees.
/// These pin that order down, because it used to depend on how the list had
/// come to be — freshly loaded (newest first from the query) or grown by an
/// optimistic add and the delta sync (appended).
void main() {
  FoodEntry entry(String id, DateTime createdAt, {MealType? meal}) => FoodEntry(
        id: id,
        userId: 'u1',
        entryDate: DateTime(2026, 8, 29),
        mealType: meal ?? MealType.breakfast,
        name: id,
        amount: 1,
        unit: 'g',
        calories: 1,
        protein: 0,
        fat: 0,
        carbs: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  final t0 = DateTime(2026, 8, 29, 8, 0);
  final t1 = DateTime(2026, 8, 29, 8, 5);
  final t2 = DateTime(2026, 8, 29, 8, 9);

  group('byLogOrder', () {
    test('sorts oldest first', () {
      final list = [entry('c', t2), entry('a', t0), entry('b', t1)]
        ..sort(DataStore.byLogOrder);
      expect(list.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('breaks ties on id so a shared timestamp is still stable', () {
      // A meal template or a repeated meal inserts several entries at once and
      // they can land on the same createdAt; without the tiebreak their order
      // would wobble between loads.
      final one = [entry('z', t0), entry('y', t0), entry('x', t0)]
        ..sort(DataStore.byLogOrder);
      final other = [entry('y', t0), entry('x', t0), entry('z', t0)]
        ..sort(DataStore.byLogOrder);
      expect(one.map((e) => e.id), ['x', 'y', 'z']);
      expect(other.map((e) => e.id), one.map((e) => e.id));
    });
  });

  group('DataStore keeps one order however the list was built', () {
    final store = DataStore.instance;
    setUp(store.resetForNewSession);

    test('entries added out of order still read oldest first', () {
      store.addFoodEntry(entry('c', t2));
      store.addFoodEntry(entry('a', t0));
      store.addFoodEntry(entry('b', t1));
      expect(store.foodEntries.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('a newly added entry lands last and does not move afterwards', () {
      store.addFoodEntry(entry('a', t0));
      store.addFoodEntry(entry('b', t1));
      final beforeAdd = store.foodEntries.map((e) => e.id).toList();

      store.addFoodEntry(entry('c', t2));
      expect(store.foodEntries.map((e) => e.id), [...beforeAdd, 'c'],
          reason: 'the newest entry belongs at the end of the log');

      // Editing it must not shuffle the list — that was visible as an entry
      // jumping position after a trivial amount change.
      store.replaceFoodEntry(entry('c', t2));
      expect(store.foodEntries.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('removing an entry leaves the rest in order', () {
      for (final e in [entry('a', t0), entry('b', t1), entry('c', t2)]) {
        store.addFoodEntry(e);
      }
      store.removeFoodEntry('b');
      expect(store.foodEntries.map((e) => e.id), ['a', 'c']);
    });

    test('order does not depend on which meal an entry belongs to', () {
      // Grouping happens in the UI; the store holds one flat, time-ordered list
      // so every meal group reads the same way.
      store.addFoodEntry(entry('lunch', t1, meal: MealType.lunch));
      store.addFoodEntry(entry('breakfast', t0));
      store.addFoodEntry(entry('snack', t2, meal: MealType.snack));
      expect(store.foodEntries.map((e) => e.id),
          ['breakfast', 'lunch', 'snack']);
    });
  });
}
