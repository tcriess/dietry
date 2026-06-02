import 'package:shared_preferences/shared_preferences.dart';

/// Device-local persistence for the first-run onboarding tour.
///
/// The flag is stored in [SharedPreferences] so it works identically for guest
/// and logged-in users without any backend round-trip. Mirrors the lightweight
/// static pattern of `HealthConnectPrefs`. The only intentional trade-off is
/// that a logged-in user on a fresh device sees the tour again — acceptable for
/// an onboarding hint.
class TutorialPrefs {
  TutorialPrefs._();

  static const _kSeenMainTutorial = 'tutorial_main_seen';

  /// True once the user has finished or skipped the main onboarding tour.
  static Future<bool> hasSeenMainTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeenMainTutorial) ?? false;
  }

  /// Marks the main onboarding tour as seen so it does not auto-start again.
  static Future<void> setSeenMainTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenMainTutorial, true);
  }

  /// Clears the seen flag. Used when the user asks to replay the tour.
  static Future<void> resetMainTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeenMainTutorial);
  }
}
