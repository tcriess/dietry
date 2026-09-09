import 'physical_activity.dart';

/// How much of a workout's burn is added to the day's calorie budget.
///
/// A 1:1 credit — burn 600 kcal, eat 600 kcal more — is the generous reading
/// of a soft number. Three effects pull the honest figure down, and they
/// multiply:
///
///  * **Double counting.** A goal built from TDEE already carries an activity
///    multiplier (see `TrackingMethod`); with `tdeeComplete` the training is
///    priced into the goal before anything is logged at all.
///  * **Gross vs. net.** `MET × kg × hours` is the *whole* energy cost of the
///    hour, resting metabolism included. Only (MET − 1)/MET of it is energy the
///    day would not have spent anyway — 87% for an 8-MET run, 71% for a walk.
///  * **Compensation.** A sizeable share of an exercise burn is absorbed by
///    lower resting expenditure and less spontaneous movement afterwards.
///
/// Which of those apply depends on how the goal was built, so there is no
/// single right number — hence a factor the user owns, resolved from the most
/// specific level that has an opinion:
///
/// ```
/// activity  →  day  →  profile default  →  1.0
/// ```
///
/// `null` at every level means 1.0, i.e. the behaviour before this existed.
class ExerciseCredit {
  ExerciseCredit._();

  /// Credit everything — the value assumed wherever nothing is configured.
  static const double full = 1.0;

  /// Accepted range. The upper bound is deliberately above [full]: crediting
  /// more than was burned models a goal set too low for training days, and a
  /// bound is what keeps a "50" typed where 0.5 was meant out of the database.
  /// Mirrors the CHECK constraints in `V10__exercise_credit_factor.sql`.
  static const double minFactor = 0.0;
  static const double maxFactor = 2.0;

  /// The factor in force, most specific level first.
  static double resolve({double? activity, double? day, double? profile}) =>
      activity ?? day ?? profile ?? full;

  /// Constrains [factor] to the range the database accepts, and rounds to the
  /// three decimals `numeric(4,3)` stores — so what the UI shows back is what
  /// was written, not a value that silently lost its tail.
  static double sanitize(double factor) {
    final clamped = factor.clamp(minFactor, maxFactor);
    return (clamped * 1000).round() / 1000;
  }

  /// Parses a whole-percent entry ("50", "62.5") into a factor. Returns null
  /// for anything unparseable or out of range, so the caller can reject it
  /// rather than store a surprise.
  static double? parsePercent(String input) {
    final text = input.trim().replaceAll('%', '').replaceAll(',', '.');
    if (text.isEmpty) return null;
    final percent = double.tryParse(text);
    if (percent == null || percent.isNaN) return null;
    if (percent < minFactor * 100 || percent > maxFactor * 100) return null;
    return sanitize(percent / 100);
  }

  /// A factor as whole percent, without a trailing `.0` on the round numbers
  /// that make up almost every real setting.
  static String formatPercent(double factor) {
    final percent = factor * 100;
    final rounded = (percent * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}%'
        : '${rounded.toStringAsFixed(1)}%';
  }

  /// The part of [activity]'s burn that reaches the budget.
  static double creditedFor(
    PhysicalActivity activity, {
    double? day,
    double? profile,
  }) =>
      (activity.caloriesBurned ?? 0) *
      resolve(activity: activity.creditFactor, day: day, profile: profile);

  /// What the whole day actually burned, before any factor is applied.
  static double grossTotal(Iterable<PhysicalActivity> activities) =>
      activities.fold(0.0, (sum, a) => sum + (a.caloriesBurned ?? 0));

  /// What the whole day's burn contributes to the budget.
  static double creditedTotal(
    Iterable<PhysicalActivity> activities, {
    double? day,
    double? profile,
  }) =>
      activities.fold(
          0.0, (sum, a) => sum + creditedFor(a, day: day, profile: profile));
}
