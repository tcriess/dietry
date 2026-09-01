import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/models.dart';
import 'package:dietry/screens/reports_screen.dart';
import 'package:dietry/services/reports_service.dart';

/// The calorie chart judges a day against the target that actually applied to
/// it: the goal in force that day, raised by what was burned. Get that wrong
/// and every training day reads as a blowout — which is exactly what a fixed
/// goal line used to claim.

DailyNutritionData _day(String date, double kcal, {double burned = 0}) =>
    DailyNutritionData(
      date: DateTime.parse(date),
      calories: kcal,
      protein: 0,
      fat: 0,
      carbs: 0,
      caloriesBurned: burned,
    );

NutritionGoal _goal(double kcal, {String? from}) => NutritionGoal(
      calories: kcal,
      protein: 0,
      fat: 0,
      carbs: 0,
      validFrom: from == null ? null : DateTime.parse(from),
    );

void main() {
  group('buildCalorieTrend', () {
    test("lifts the target by the day's burn, leaves intake gross", () {
      final pts = buildCalorieTrend(
        [
          _day('2026-03-02', 2100),
          _day('2026-03-03', 2350, burned: 480),
        ],
        [_goal(2200)],
        ReportRange.week,
      );

      expect(pts.map((p) => p.intake), [2100, 2350]);
      expect(pts.map((p) => p.burned), [0, 480]);
      expect(pts.map((p) => p.target), [2200, 2680]);
    });

    test('follows the goal history rather than the newest goal', () {
      final pts = buildCalorieTrend(
        [_day('2026-03-02', 2000, burned: 100), _day('2026-03-10', 2000)],
        // Descending by validFrom, as getAllGoals() returns them.
        [_goal(1900, from: '2026-03-05'), _goal(2200, from: '2026-01-01')],
        ReportRange.week,
      );

      expect(pts[0].target, 2300); // old goal + burn
      expect(pts[1].target, 1900); // new goal, nothing burned
    });

    test('averages within a bucket for the coarse ranges', () {
      final pts = buildCalorieTrend(
        [
          _day('2026-03-02', 2000, burned: 0),
          _day('2026-03-03', 3000, burned: 400),
        ],
        [_goal(2200)],
        ReportRange.allTime,
      );

      expect(pts, hasLength(1));
      expect(pts.single.intake, 2500);
      expect(pts.single.burned, 200);
      expect(pts.single.target, 2400);
    });

    test('target is null while no goal was ever set', () {
      final pts = buildCalorieTrend(
        [_day('2026-03-02', 2000, burned: 300)],
        const [],
        ReportRange.week,
      );

      expect(pts.single.target, isNull);
      expect(pts.single.intake, 2000);
    });

    test('a bucket averages the target only over days that had a goal', () {
      final pts = buildCalorieTrend(
        [
          _day('2026-03-02', 2000, burned: 500), // before any goal existed
          _day('2026-03-03', 2000, burned: 100),
        ],
        [_goal(2200, from: '2026-03-03')],
        ReportRange.allTime,
      );

      expect(pts.single.target, 2300);
      expect(pts.single.burned, 300); // …while the burn average covers both
    });

    test('orders buckets ascending regardless of grouping', () {
      final pts = buildCalorieTrend(
        [
          _day('2025-11-04', 2000),
          _day('2025-12-04', 2100),
          _day('2026-01-04', 2200),
        ],
        [_goal(2000)],
        ReportRange.allTime,
      );

      expect(pts.map((p) => p.date.month), [11, 12, 1]);
      expect(pts.map((p) => p.date.year), [2025, 2025, 2026]);
    });
  });
}
