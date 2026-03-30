import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';

/// Manages custom server endpoint configuration for self-hosted CE deployments.
/// Only active in the community edition — cloud edition always uses compiled-in URLs.
class ServerConfigService {
  static const _keyDataApiUrl = 'server_config_data_api_url';
  static const _keyAuthBaseUrl = 'server_config_auth_base_url';

  /// Returns the effective data API URL: custom if set, else compiled-in default.
  static Future<String> getDataApiUrl() async {
    if (AppConfig.isCloudEdition) return AppConfig.dataApiUrl;
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyDataApiUrl);
    return (custom != null && custom.isNotEmpty) ? custom : AppConfig.dataApiUrl;
  }

  /// Returns the effective auth base URL: custom if set, else compiled-in default.
  static Future<String> getAuthBaseUrl() async {
    if (AppConfig.isCloudEdition) return AppConfig.authBaseUrl;
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyAuthBaseUrl);
    return (custom != null && custom.isNotEmpty) ? custom : AppConfig.authBaseUrl;
  }

  /// Persists custom URLs. Pass empty strings to revert to defaults.
  static Future<void> save({
    required String dataApiUrl,
    required String authBaseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDataApiUrl, dataApiUrl.trim());
    await prefs.setString(_keyAuthBaseUrl, authBaseUrl.trim());
  }

  /// Clears any stored custom URLs, reverting to compiled-in defaults.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDataApiUrl);
    await prefs.remove(_keyAuthBaseUrl);
  }

  /// Returns true if the user has stored a custom data API URL.
  static Future<bool> hasCustomConfig() async {
    if (AppConfig.isCloudEdition) return false;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyDataApiUrl);
    return url != null && url.isNotEmpty;
  }

  /// Synchronous read — returns null if not yet loaded or not set.
  /// Use [getDataApiUrl] for the authoritative value.
  static String? _cachedDataApiUrl;
  static String? _cachedAuthBaseUrl;

  /// Load custom URLs into the cache so that services can read them
  /// synchronously after startup. Call once from main() after init.
  static Future<void> loadIntoCache() async {
    if (AppConfig.isCloudEdition) return;
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getString(_keyDataApiUrl);
    final a = prefs.getString(_keyAuthBaseUrl);
    _cachedDataApiUrl = (d != null && d.isNotEmpty) ? d : null;
    _cachedAuthBaseUrl = (a != null && a.isNotEmpty) ? a : null;
  }

  /// Update cache after the user saves new values (no restart needed).
  static void updateCache({required String dataApiUrl, required String authBaseUrl}) {
    _cachedDataApiUrl = dataApiUrl.trim().isEmpty ? null : dataApiUrl.trim();
    _cachedAuthBaseUrl = authBaseUrl.trim().isEmpty ? null : authBaseUrl.trim();
  }

  /// Effective data API URL — falls back to AppConfig if no custom value cached.
  static String get effectiveDataApiUrl =>
      _cachedDataApiUrl ?? AppConfig.dataApiUrl;

  /// Effective auth base URL — falls back to AppConfig if no custom value cached.
  static String get effectiveAuthBaseUrl =>
      _cachedAuthBaseUrl ?? AppConfig.authBaseUrl;
}
