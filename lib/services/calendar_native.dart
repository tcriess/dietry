// Android / iOS implementation, reading the OS calendar provider.
//
// Read-only by design: the app never writes to the user's calendar. Exporting
// nutrition data goes out as an .ics file the user imports themselves (see
// nutrition_ics_export.dart), which keeps us out of their calendars entirely.
import 'package:device_calendar/device_calendar.dart';

import '../models/calendar_event.dart';
import 'app_logger.dart';

final _plugin = DeviceCalendarPlugin();

/// Whether calendar access was already granted, without prompting.
Future<bool> hasCalendarPermission() async {
  try {
    final result = await _plugin.hasPermissions();
    return result.isSuccess && (result.data ?? false);
  } catch (e) {
    appLogger.w('⚠️ Calendar permission check failed: $e');
    return false;
  }
}

Future<bool> requestCalendarPermission() async {
  try {
    if (await hasCalendarPermission()) return true;
    final result = await _plugin.requestPermissions();
    return result.isSuccess && (result.data ?? false);
  } catch (e) {
    appLogger.e('❌ Calendar permission request failed: $e');
    return false;
  }
}

/// All-day events from every calendar on the device, between [start] and [end].
///
/// Timed events are dropped: a holiday is an all-day affair, and letting a
/// 14:00 dentist appointment through would offer to mark that day a cheat day.
Future<List<CalendarEvent>> fetchAllDayEvents({
  required DateTime start,
  required DateTime end,
}) async {
  try {
    final calendars = await _plugin.retrieveCalendars();
    if (!calendars.isSuccess || calendars.data == null) {
      appLogger.w('⚠️ Could not retrieve calendars');
      return const [];
    }

    final events = <CalendarEvent>[];
    for (final calendar in calendars.data!) {
      final id = calendar.id;
      if (id == null) continue;
      try {
        final result = await _plugin.retrieveEvents(
          id,
          RetrieveEventsParams(startDate: start, endDate: end),
        );
        if (!result.isSuccess || result.data == null) continue;

        for (final event in result.data!) {
          if (event.allDay != true) continue;
          final converted = _toCalendarEvent(event, calendar.name);
          if (converted != null) events.add(converted);
        }
      } catch (e) {
        // One unreadable calendar (a broken subscription, a revoked account)
        // must not cost the user the rest of them.
        appLogger.w('⚠️ Could not read calendar "${calendar.name}": $e');
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));
    appLogger.i('📅 Found ${events.length} all-day calendar events');
    return events;
  } catch (e) {
    appLogger.e('❌ Calendar read failed: $e');
    return const [];
  }
}

/// Normalises a provider event into a date-only, inclusive-end range.
///
/// Both CalendarContract and RFC 5545 store an all-day event's end date
/// *exclusively* — 10–12 August is held as 10 August to 13 August 00:00 — so
/// taking it at face value would add a spurious trailing day to every imported
/// holiday. The subtraction below undoes that. It is only applied when the end
/// lands exactly on midnight and after the start, so a provider that already
/// reports an inclusive end cannot be shortened by it.
///
/// This stays a best guess across calendar backends, which is the reason the
/// picked event only ever *prefills* the date-range picker: the user sees the
/// range and confirms it before a single cheat day is written.
CalendarEvent? _toCalendarEvent(Event event, String? calendarName) {
  final rawStart = event.start;
  final rawEnd = event.end;
  if (rawStart == null) return null;

  final startDate = DateTime(rawStart.year, rawStart.month, rawStart.day);
  DateTime endDate = rawEnd == null
      ? startDate
      : DateTime(rawEnd.year, rawEnd.month, rawEnd.day);

  final endsAtMidnight =
      rawEnd != null && rawEnd.hour == 0 && rawEnd.minute == 0;
  if (endsAtMidnight && endDate.isAfter(startDate)) {
    endDate = endDate.subtract(const Duration(days: 1));
  }
  if (endDate.isBefore(startDate)) endDate = startDate;

  final title = event.title?.trim();
  return CalendarEvent(
    id: event.eventId ?? '${startDate.toIso8601String()}-$title',
    title: (title == null || title.isEmpty) ? '—' : title,
    start: startDate,
    end: endDate,
    calendarName: calendarName,
  );
}
