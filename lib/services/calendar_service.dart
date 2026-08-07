import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/calendar_event.dart';
import '../platform_utils.dart';

// Conditional import: the device_calendar plugin only exists on mobile.
import 'calendar_stub.dart' if (dart.library.io) 'calendar_native.dart';

/// Read-only access to the phone's calendar, used to prefill a holiday's date
/// range from an event the user already put in their calendar.
///
/// Goes through the OS calendar provider, which means every account the phone
/// syncs — Google, Outlook, iCloud — is covered without the app ever holding a
/// calendar OAuth token or a shared secret URL.
///
/// Nothing here writes to the calendar, and nothing acts on an event on its
/// own: the caller shows what was found and the user confirms it. A cheat day
/// takes the day out of the nutrition reports, so silently marking days because
/// of an event title would quietly falsify the user's own statistics.
class CalendarService {
  /// Mobile only. Web and desktop get the stub, so the feature is hidden rather
  /// than offered and then failing.
  static bool get isSupported => !kIsWeb && (isAndroid() || isIOS());

  /// Whether permission is already granted, without prompting.
  Future<bool> hasPermission() => hasCalendarPermission();

  /// Prompts for calendar permission if it isn't granted yet.
  Future<bool> requestPermission() => requestCalendarPermission();

  /// All-day events across every calendar on the device, sorted by start date.
  ///
  /// [end] is inclusive of the day it falls on.
  Future<List<CalendarEvent>> allDayEvents({
    required DateTime start,
    required DateTime end,
  }) =>
      fetchAllDayEvents(start: start, end: end);
}
