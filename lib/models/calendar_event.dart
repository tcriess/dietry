/// One all-day entry read from the phone's calendar, reduced to what declaring
/// a holiday needs.
///
/// Deliberately a plain model rather than the `device_calendar` `Event`: the
/// stub used on web and desktop must be able to satisfy the same API without
/// the plugin being linked in at all.
class CalendarEvent {
  /// The calendar provider's event id. Unused today — kept because a future
  /// recurring sync needs a stable handle to recognise an event it already
  /// imported (see docs/calendar_integration.md).
  final String id;

  final String title;

  /// First day of the event, date-only.
  final DateTime start;

  /// Last day of the event, date-only and **inclusive** — unlike the calendar
  /// provider's own exclusive end date, which is normalised away on the way in.
  final DateTime end;

  /// Name of the calendar it came from ("Work", "Family", …). Shown so two
  /// identically-titled events from different accounts can be told apart.
  final String? calendarName;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.calendarName,
  });

  /// Number of days the event covers, both ends included.
  int get dayCount => end.difference(start).inDays + 1;
}
