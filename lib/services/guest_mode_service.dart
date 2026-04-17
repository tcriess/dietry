import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

/// Guest mode service — manage whether the app is in local-only mode.
///
/// When enabled, all data is stored locally in SQLite.
/// No authentication, no remote sync.
class GuestModeService {
  static const String _key = 'guest_mode_active';
  static bool _cached = false;
  static bool _wasGuestMode = false;  // Track if user was in guest mode before login

  /// Initialize from SharedPreferences (call once at startup)
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cached = prefs.getBool(_key) ?? false;
      _wasGuestMode = _cached;  // Remember initial state for migration
      appLogger.i('🔍 GuestModeService initialized: $_cached');
    } catch (e) {
      appLogger.e('❌ Error initializing GuestModeService: $e');
      _cached = false;
      _wasGuestMode = false;
    }
  }

  /// Is guest mode currently active?
  static bool get isGuestMode => _cached;

  /// Was user in guest mode before login?
  static bool get wasGuestMode => _wasGuestMode;

  /// Enable guest mode and persist
  static Future<void> enable() async {
    try {
      appLogger.d('[GuestModeService.enable] starting...');
      final prefs = await SharedPreferences.getInstance();
      appLogger.d('[GuestModeService.enable] got prefs instance');

      await prefs.setBool(_key, true);
      appLogger.d('[GuestModeService.enable] setBool completed');

      _cached = true;
      appLogger.d('[GuestModeService.enable] _cached set to true, isGuestMode=$isGuestMode');

      // Verify it was written
      final verification = prefs.getBool(_key) ?? false;
      appLogger.d('[GuestModeService.enable] verification: stored=$verification, cached=$_cached');

      appLogger.i('✅ Guest mode enabled');
    } catch (e) {
      appLogger.e('❌ Error enabling guest mode: $e');
      rethrow;
    }
  }

  /// Disable guest mode and persist
  static Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, false);
      _cached = false;
      appLogger.i('✅ Guest mode disabled');
    } catch (e) {
      appLogger.e('❌ Error disabling guest mode: $e');
    }
  }
}
