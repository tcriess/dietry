import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_logger.dart';

bool _tzInitialized = false;

/// Loads the timezone database and sets [tz.local] to the device's IANA zone.
///
/// Without this, `tz_data.initializeTimeZones()` leaves `tz.local` at its
/// default of UTC, so any `zonedSchedule` fires at the wrong wall-clock time
/// (shifted by the device's UTC offset). Idempotent and safe to call from
/// multiple reminder services; falls back to UTC if the platform timezone
/// can't be resolved.
Future<void> ensureLocalTimezone() async {
  if (_tzInitialized) return;
  tz_data.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
    _tzInitialized = true;
  } catch (e) {
    // Leave tz.local at UTC; better than crashing. Don't mark initialized so a
    // later call can retry once the platform channel is available.
    appLogger.w('⚠️ Could not resolve local timezone, using UTC: $e');
  }
}
