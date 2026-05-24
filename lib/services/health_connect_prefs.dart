import 'package:shared_preferences/shared_preferences.dart';
import 'health_connect_service.dart';

/// Device-local preferences for Health Connect / HealthKit integration.
///
/// Stored in SharedPreferences; not synced to the backend. Toggling on one
/// device does not affect others.
class HealthConnectPrefs {
  static const _kEnabled = 'hc_enabled';
  static const _kLastSyncAt = 'hc_last_sync_at_ms';

  /// Whether HC import is enabled. Defaults to `true` on supported platforms
  /// (Android / iOS) and `false` elsewhere.
  static Future<bool> isEnabled() async {
    if (!HealthConnectService.isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  /// Timestamp of the last successful HC import. Null if never imported.
  static Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastSyncAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setLastSyncAt(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSyncAt, when.millisecondsSinceEpoch);
  }
}
