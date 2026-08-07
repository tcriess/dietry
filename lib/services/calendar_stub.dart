// Stub for web and desktop — the device_calendar plugin has no implementation
// there, so the whole feature is hidden rather than failing at runtime.
import '../models/calendar_event.dart';

Future<bool> hasCalendarPermission() async => false;

Future<bool> requestCalendarPermission() async => false;

Future<List<CalendarEvent>> fetchAllDayEvents({
  required DateTime start,
  required DateTime end,
}) async =>
    const [];
