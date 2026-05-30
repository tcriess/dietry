import 'dart:ui' as ui;

/// Localized title/body for background reminder notifications.
///
/// Reminders fire without a BuildContext, so they can't use AppLocalizations.
/// We resolve the device's locale (clamped to a supported language) at the time
/// the notification is built/scheduled. The in-app language override isn't
/// persisted across restarts, and scheduled notifications outlive the app, so
/// the platform locale is the right effective source here.
class ReminderStrings {
  static const _supported = {'de', 'en', 'es'};

  static String _lang() {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    return _supported.contains(code) ? code : 'en';
  }

  static String _pick(Map<String, String> m) => m[_lang()] ?? m['en']!;

  static String get waterTitle => _pick(const {
        'de': '💧 Zeit zum Trinken!',
        'en': '💧 Time to drink!',
        'es': '💧 ¡Hora de beber!',
      });

  static String get waterBody => _pick(const {
        'de': 'Denk daran, regelmäßig zu trinken.',
        'en': 'Remember to drink water regularly.',
        'es': 'Recuerda beber agua con regularidad.',
      });

  static String get foodTitle => _pick(const {
        'de': '🍽️ Schon etwas gegessen?',
        'en': '🍽️ Logged your meals?',
        'es': '🍽️ ¿Registraste tus comidas?',
      });

  static String get foodBody => _pick(const {
        'de': 'Vergiss nicht, deine Mahlzeiten einzutragen.',
        'en': "Don't forget to log your meals.",
        'es': 'No olvides registrar tus comidas.',
      });
}
