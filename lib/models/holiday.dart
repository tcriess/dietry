import 'cheat_day.dart';

/// A named run of cheat days declared in one go — a vacation, Christmas, a
/// long weekend.
///
/// A holiday has no row of its own: it is the set of [CheatDay]s that share a
/// `holiday_id`, folded back together for display. That is why [start] and
/// [end] are derived rather than stored, and why [dayCount] can be smaller than
/// the calendar span — the user may have un-cheated individual days inside it.
class Holiday {
  final String id;
  final String? label;

  /// First and last cheat day still belonging to this holiday (inclusive).
  final DateTime start;
  final DateTime end;

  /// Cheat days actually present. Equals the calendar span unless days were
  /// removed individually.
  final int dayCount;

  const Holiday({
    required this.id,
    this.label,
    required this.start,
    required this.end,
    required this.dayCount,
  });

  /// Calendar days from [start] to [end] inclusive.
  int get spanDays => end.difference(start).inDays + 1;

  /// True when individual days inside the range are no longer cheat days.
  bool get hasGaps => dayCount < spanDays;

  bool get isPast => end.isBefore(_today);

  bool get isUpcoming => start.isAfter(_today);

  bool get isCurrent => !isPast && !isUpcoming;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Folds a flat list of cheat days into holidays, newest first.
  ///
  /// Days with no `holiday_id` are ignored — they are hand-toggled one-offs and
  /// are not managed through the holiday UI.
  static List<Holiday> groupFrom(Iterable<CheatDay> days) {
    final byHoliday = <String, List<CheatDay>>{};
    for (final d in days) {
      final hid = d.holidayId;
      if (hid == null) continue;
      byHoliday.putIfAbsent(hid, () => []).add(d);
    }

    final result = byHoliday.entries.map((e) {
      final dates = e.value.map((d) => _dateOnly(d.cheatDate)).toList()..sort();
      return Holiday(
        id: e.key,
        // Every row of a holiday carries the same label; take the first
        // non-empty one so a partially-written note still shows.
        label: e.value
            .map((d) => d.note)
            .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null),
        start: dates.first,
        end: dates.last,
        dayCount: dates.length,
      );
    }).toList();

    result.sort((a, b) => b.start.compareTo(a.start));
    return result;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
