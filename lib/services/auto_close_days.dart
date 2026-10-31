import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';
import 'data_store.dart';

/// Closes past days with food entries once a grace period has passed.
///
/// Device-local, like the reminder toggles. Progress is a "closed through"
/// date per account: only days after it are considered, so a day the user
/// reopens is never closed again.
class AutoCloseDays {
  AutoCloseDays._();

  static const _kEnabled = 'auto_close_days_enabled';
  static const _kClosedThroughPrefix = 'auto_close_through_';

  /// With 1, yesterday stays open all of today.
  static const graceDays = 1;

  /// How far back a first run reaches — existing history stays as it is.
  static const firstRunLookbackDays = 7;

  static bool _running = false;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  /// Turning it off forgets the progress, so turning it back on later starts
  /// like a first run instead of closing everything since.
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (!enabled) {
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_kClosedThroughPrefix)) await prefs.remove(key);
      }
    }
  }

  /// The days due for closing at [now], or null when none are.
  @visibleForTesting
  static ({DateTime from, DateTime to})? window(
      DateTime now, DateTime? closedThrough) {
    final to = DateTime(now.year, now.month, now.day - graceDays - 1);
    final from = closedThrough != null
        ? DateTime(
            closedThrough.year, closedThrough.month, closedThrough.day + 1)
        : DateTime(to.year, to.month, to.day - firstRunLookbackDays + 1);
    return from.isAfter(to) ? null : (from: from, to: to);
  }

  /// Closes the days that came due since the last run and returns how many.
  /// [scope] keys the progress — the user id, or 'guest'. Never throws; on
  /// failure the progress stays put and the next run retries.
  static Future<int> run(
    String scope, {
    DateTime? now,
    Future<Set<DateTime>> Function(DateTime from, DateTime to)? findDays,
    Future<void> Function(Iterable<DateTime> days)? closeDays,
  }) async {
    if (_running) return 0;
    _running = true;
    try {
      if (!await isEnabled()) return 0;
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kClosedThroughPrefix$scope';
      final stored = prefs.getString(key);
      final w = window(
          now ?? DateTime.now(), stored == null ? null : DateTime.parse(stored));
      if (w == null) return 0;

      final store = DataStore.instance;
      final days =
          (await (findDays ?? store.foodEntryDatesInRange)(w.from, w.to))
              .toList()
            ..sort();
      await (closeDays ?? store.closeDays)(days);
      await prefs.setString(key, w.to.toIso8601String().split('T')[0]);
      if (days.isNotEmpty) appLogger.i('🔒 Auto-closed ${days.length} day(s)');
      return days.length;
    } catch (e) {
      appLogger.w('⚠️ Auto-close skipped: $e');
      return 0;
    } finally {
      _running = false;
    }
  }
}
