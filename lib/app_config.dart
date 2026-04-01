/// Zentrale App-Konfiguration — Werte werden zur Build-Zeit via
/// `--dart-define-from-file=config/prod.json` gesetzt.
///
/// Ohne explizite Defines werden die Development-Defaults verwendet.
/// Niemals Produktions-Credentials in den Code committen.
class AppConfig {
  // ── Datenbank / PostgREST ─────────────────────────────────────────────────

  static const String dataApiUrl = String.fromEnvironment('DATA_API_URL');

  static const String authBaseUrl = String.fromEnvironment('AUTH_BASE_URL');

  /// Origin of this app (e.g. https://www.dietry.de or http://localhost:8080).
  /// Required for email auth requests so Better Auth can validate the caller.
  /// Falls back to localhost:8080 in development if not explicitly configured.
  static const String _appOriginConfigured =
      String.fromEnvironment('APP_ORIGIN', defaultValue: '');

  static String get appOrigin {
    if (_appOriginConfigured.isNotEmpty) return _appOriginConfigured;
    if (isDevelopment) return 'http://localhost:8080';
    return '';
  }

  /// Full URL of the password-reset page sent in reset emails.
  /// Must be in the trusted-origins list of the Neon Auth project.
  /// On web: derived at runtime from the browser origin (see NeonAuthService).
  /// On native: must be set via PASSWORD_RESET_REDIRECT_URL in the config file.
  static const String passwordResetRedirectUrl =
      String.fromEnvironment('PASSWORD_RESET_REDIRECT_URL');

  /// OAuth callback URL registered for Android deep links.
  /// Must match exactly what is configured as a trusted redirect in Neon Auth.
  /// Set via ANDROID_CALLBACK_URL in the config file.
  static const String androidCallbackUrl =
      String.fromEnvironment('ANDROID_CALLBACK_URL');

  // ── Externe APIs ──────────────────────────────────────────────────────────

  /// USDA FoodData Central — https://fdc.nal.usda.gov/api-guide.html
  /// Kostenloser API-Key unter https://api.data.gov/signup/
  /// Nur in nativen Builds gesetzt (Key nicht im Web-Bundle).
  /// Attribution: "Data sourced from USDA FoodData Central"
  static const String usdaApiKey = String.fromEnvironment('USDA_API_KEY');
  static bool get hasUsda => usdaApiKey.isNotEmpty;

  /// Open Food Facts — https://world.openfoodfacts.org/
  /// Kein Key erforderlich. Attribution Pflicht (ODbL):
  /// "Data from Open Food Facts (openfoodfacts.org)"
  /// Auf Web und Native verfügbar.

  // Edamam (aktuell nicht aktiv, kostenpflichtig)
  static const String edamamAppId = String.fromEnvironment('EDAMAM_APP_ID');
  static const String edamamAppKey = String.fromEnvironment('EDAMAM_APP_KEY');
  static bool get hasEdamam =>
      edamamAppId.isNotEmpty && edamamAppKey.isNotEmpty;

  // ── Umgebung ──────────────────────────────────────────────────────────────

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  // ── Edition ───────────────────────────────────────────────────────────────

  /// Build-Zeit-Edition: `community` (default) oder `cloud`.
  /// Steuert ob Premium-Features überhaupt erreichbar sind.
  static const String edition = String.fromEnvironment(
    'EDITION',
    defaultValue: 'community',
  );

  /// True wenn dieser Build die Cloud-Edition ist (Premium-Features möglich).
  static bool get isCloudEdition => edition == 'cloud';

  // ── Build-Metadaten ───────────────────────────────────────────────────────

  /// Short git commit hash injected by CI via --dart-define=GIT_HASH=...
  /// Falls back to 'dev' for local builds.
  static const String gitHash = String.fromEnvironment(
    'GIT_HASH',
    defaultValue: 'dev',
  );

  /// ISO date of the build injected by CI via --dart-define=BUILD_DATE=...
  /// Empty for local builds.
  static const String buildDate = String.fromEnvironment('BUILD_DATE');
}
