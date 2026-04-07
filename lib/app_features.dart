import 'dart:io' as io show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'app_config.dart';
import 'services/jwt_helper.dart';

// Lokaler Test-Override: --dart-define=PREMIUM_ROLE=pro
// Nur wirksam wenn EDITION=cloud. Nie in Produktion setzen.
const _kPremiumRoleOverride = String.fromEnvironment('PREMIUM_ROLE');

/// Zentrales Feature-Gate-Register.
///
/// Kombiniert zwei Ebenen:
///   1. Build-Zeit: [AppConfig.isCloudEdition] — Community vs. Cloud
///   2. Laufzeit:   JWT `role`-Claim — Free / Basic / Pro innerhalb Cloud
///
/// Community-Builds: alle Premium-Gates geben immer `false` zurück.
/// Cloud-Builds: Gates abhängig vom JWT-Claim nach dem Login.
///
/// Verwendung:
/// ```dart
/// if (AppFeatures.mealTemplates) { ... }
/// ```
class AppFeatures {
  AppFeatures._();

  static String _role = 'community';

  /// Initialisiert AppFeatures mit dem PREMIUM_ROLE-Override (vor dem Login).
  /// Wird einmal beim App-Start aufgerufen, wenn PREMIUM_ROLE gesetzt ist.
  /// Nur für Entwicklung/Tests (wird vom PREMIUM_ROLE dart-define überschrieben).
  static void initializeFromEnvironment() {
    if (_kPremiumRoleOverride.isNotEmpty && AppConfig.isCloudEdition) {
      _role = _kPremiumRoleOverride;
    }
  }

  /// Setzt die Rolle aus dem JWT-Payload nach erfolgreichem Login.
  /// Wird von [_onAuthChanged] in main.dart aufgerufen.
  static void setFromJwt(String jwt) {
    final payload = JwtHelper.decodeToken(jwt);
    final jwtRole = payload?['role'] as String? ?? 'free';
    // PREMIUM_ROLE dart-define überschreibt JWT-Rolle (nur für lokale Tests)
    _role = (_kPremiumRoleOverride.isNotEmpty && AppConfig.isCloudEdition)
        ? _kPremiumRoleOverride
        : jwtRole;
  }

  /// Setzt die Rolle zurück (beim Logout).
  static void reset() => _role = 'community';

  /// Aktuelle Rolle des eingeloggten Nutzers.
  static String get role => _role;

  // ── Editions-Check ────────────────────────────────────────────────────────

  static bool get _isCloud => AppConfig.isCloudEdition;

  /// True if platform supports native file sharing (mobile only).
  static bool get _platformSupportsSocialSharing {
    // File sharing to social media apps only works on Android and iOS
    if (kIsWeb) return false;
    return io.Platform.isAndroid || io.Platform.isIOS;
  }

  // ── Rollen-Checks ─────────────────────────────────────────────────────────

  /// True für Basic- und Pro-Nutzer (Cloud).
  static bool get isBasic => _isCloud && (_role == 'basic' || _role == 'pro');

  /// True nur für Pro-Nutzer (Cloud).
  static bool get isPro => _isCloud && _role == 'pro';

  // ── Feature-Gates ─────────────────────────────────────────────────────────
  // Jedes neue Premium-Feature bekommt hier einen Getter.
  // Community-Edition: immer false (kein isCloud-Check nötig, da _isCloud=false).

  /// Mahlzeiten-Vorlagen: mehrere Zutaten mit Prozentanteilen als eine Mahlzeit.
  static bool get mealTemplates => isBasic;

  /// Mikronährstoffe & Vitamine pro Food-Entry.
  static bool get microNutrients => isBasic;

  /// Schnell-Eintrag für Aktivitäten: Zuletzt / Favoriten / Kurzbefehle (Premium).
  static bool get activityQuickAdd => isBasic;

  /// Streak-Tracking mit persistenten Rekorden, Meilensteinen und Badges.
  /// Kostenlos für alle Cloud-Nutzer (kein Premium-Abo erforderlich).
  static bool get streaks => _isCloud;

  /// Berichte-Export als CSV.
  /// Kostenlos für alle Cloud-Nutzer (kein Premium-Abo erforderlich).
  static bool get reportsExport => _isCloud;

  /// Share progress cards on social media (Streak, Daily Goals).
  /// Kostenlos für alle Cloud-Nutzer (kein Premium-Abo erforderlich).
  /// Only available on Android and iOS (mobile platforms with native sharing).
  static bool get shareProgress => _isCloud && _platformSupportsSocialSharing;

  /// Erweiterte Analysen: Wochen-/Monatsberichte, Trend-Charts.
  static bool get advancedAnalytics => isPro;

  /// Mehrere Profile (Familie / Trainer-Klienten).
  static bool get multipleProfiles => isPro;
}
