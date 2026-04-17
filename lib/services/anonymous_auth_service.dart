import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_logger.dart';
import 'jwt_helper.dart';

/// Service for fetching and managing anonymous JWT tokens.
///
/// In guest mode, anonymous tokens provide read-only access to public foods
/// from the database without requiring user authentication.
class AnonymousAuthService {
  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  /// Fetch anonymous JWT from Neon Auth. Returns null if endpoint not available.
  ///
  /// The token is cached and reused until it expires (5 minute buffer).
  /// If expired, a new token is automatically fetched.
  static Future<String?> getToken(String authBaseUrl) async {
    // Return cached token if still valid (5 min buffer)
    if (_cachedToken != null && _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(Duration(minutes: 5)))) {
      appLogger.d('♻️ Using cached anonymous token');
      return _cachedToken;
    }

    try {
      appLogger.d('🔓 Fetching anonymous token from $authBaseUrl/token/anonymous');
      final resp = await http.get(Uri.parse('$authBaseUrl/token/anonymous')).timeout(
        Duration(seconds: 5),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _cachedToken = data['token'] as String?;

        if (_cachedToken != null) {
          // Decode JWT to extract expiry
          try {
            final payload = JwtHelper.decodeToken(_cachedToken!);
            if (payload != null) {
              final exp = payload['exp'] as int?;
              if (exp != null) {
                _tokenExpiry =
                    DateTime.fromMillisecondsSinceEpoch(exp * 1000);
                appLogger.i('🔓 Anonymous token fetched, expires at $_tokenExpiry');
              } else {
                // Fallback: assume 1 hour expiry
                _tokenExpiry = DateTime.now().add(Duration(hours: 1));
                appLogger.w('⚠️ No exp claim in anonymous token, assuming 1h expiry');
              }
            } else {
              // Failed to decode token
              _tokenExpiry = DateTime.now().add(Duration(hours: 1));
              appLogger.w('⚠️ Failed to decode anonymous token payload');
            }
          } catch (e) {
            appLogger.w('⚠️ Failed to decode anonymous token: $e');
            _tokenExpiry = DateTime.now().add(Duration(hours: 1));
          }
          return _cachedToken;
        }
      } else {
        appLogger.w('⚠️ Anonymous token endpoint returned ${resp.statusCode}');
      }
    } catch (e) {
      appLogger.w('⚠️ Failed to fetch anonymous token: $e');
    }

    return null; // endpoint not available or failed
  }

  /// Clear cached token (for testing or logout).
  static void clearCache() {
    _cachedToken = null;
    _tokenExpiry = null;
    appLogger.d('🔓 Cleared anonymous token cache');
  }
}
