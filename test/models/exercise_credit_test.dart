import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/exercise_credit.dart';
import 'package:dietry/models/physical_activity.dart';

/// The whole point of the feature is that a burn no longer counts one-for-one
/// towards the day's budget — and that the number counted comes from the most
/// specific level that has an opinion. Get the precedence wrong and a user who
/// set "half" on one hike silently applies it to the whole week, or a profile
/// default quietly overrules a day they deliberately adjusted.

PhysicalActivity _activity(double? kcal, {double? factor}) => PhysicalActivity(
      startTime: DateTime(2026, 3, 2, 7),
      endTime: DateTime(2026, 3, 2, 8),
      caloriesBurned: kcal,
      creditFactor: factor,
    );

void main() {
  group('resolve', () {
    test('credits everything when no level has an opinion', () {
      expect(ExerciseCredit.resolve(), ExerciseCredit.full);
      expect(ExerciseCredit.resolve(activity: null, day: null, profile: null),
          1.0);
    });

    test('the profile default applies when nothing more specific does', () {
      expect(ExerciseCredit.resolve(profile: 0.5), 0.5);
    });

    test('the day beats the profile', () {
      expect(ExerciseCredit.resolve(day: 0.8, profile: 0.5), 0.8);
    });

    test('the activity beats both', () {
      expect(ExerciseCredit.resolve(activity: 1.0, day: 0.8, profile: 0.5), 1.0);
    });

    test('a zero at any level is an opinion, not an absent one', () {
      // The bug this guards: `activity ?? day` written as `activity > 0 ? …`,
      // which would make "ignore this workout entirely" fall through instead.
      expect(ExerciseCredit.resolve(activity: 0, day: 0.8, profile: 0.5), 0);
      expect(ExerciseCredit.resolve(day: 0, profile: 0.5), 0);
    });
  });

  group('creditedFor', () {
    test('applies the resolved factor to the burn', () {
      expect(ExerciseCredit.creditedFor(_activity(600), profile: 0.5), 300);
      expect(ExerciseCredit.creditedFor(_activity(600), day: 0.25, profile: 0.5),
          150);
      expect(
          ExerciseCredit.creditedFor(_activity(600, factor: 1.0),
              day: 0.25, profile: 0.5),
          600);
    });

    test('an activity with no calories contributes nothing', () {
      expect(ExerciseCredit.creditedFor(_activity(null), profile: 0.5), 0);
    });
  });

  group('totals', () {
    final day = [
      _activity(600), // follows the day
      _activity(200, factor: 0), // deliberately not counted
      _activity(100, factor: 1.0), // deliberately counted in full
      _activity(null), // no calorie figure at all
    ];

    test('the gross total ignores every factor', () {
      expect(ExerciseCredit.grossTotal(day), 900);
    });

    test('the credited total applies each activity its own factor', () {
      // 600×0.5 + 200×0 + 100×1.0
      expect(ExerciseCredit.creditedTotal(day, day: 0.5), 400);
    });

    test('with nothing configured the two totals agree', () {
      expect(ExerciseCredit.creditedTotal([_activity(600), _activity(300)]),
          ExerciseCredit.grossTotal([_activity(600), _activity(300)]));
    });
  });

  group('parsePercent', () {
    test('reads whole and fractional percentages', () {
      expect(ExerciseCredit.parsePercent('50'), 0.5);
      expect(ExerciseCredit.parsePercent(' 75 '), 0.75);
      expect(ExerciseCredit.parsePercent('62.5'), 0.625);
      expect(ExerciseCredit.parsePercent('62,5'), 0.625); // German keyboard
      expect(ExerciseCredit.parsePercent('50%'), 0.5);
      expect(ExerciseCredit.parsePercent('0'), 0);
    });

    test('rejects what the database would refuse', () {
      // The typo this exists for: 0.5 typed into a field asking for percent.
      expect(ExerciseCredit.parsePercent('-1'), isNull);
      expect(ExerciseCredit.parsePercent('201'), isNull);
      expect(ExerciseCredit.parsePercent(''), isNull);
      expect(ExerciseCredit.parsePercent('abc'), isNull);
    });

    test('rounds to the three decimals the column stores', () {
      // 33.3333% would otherwise come back as a factor the database truncates,
      // and the UI would then show a value that was never written.
      expect(ExerciseCredit.parsePercent('33.3333'), 0.333);
    });
  });

  group('formatPercent', () {
    test('drops the decimal on the round numbers people actually set', () {
      expect(ExerciseCredit.formatPercent(0.5), '50%');
      expect(ExerciseCredit.formatPercent(1.0), '100%');
      expect(ExerciseCredit.formatPercent(0), '0%');
    });

    test('keeps one decimal when there is one', () {
      expect(ExerciseCredit.formatPercent(0.625), '62.5%');
    });
  });
}
