import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dietry/services/app_logger.dart';

/// Helper-Funktionen für JWT-Token-Handling
class JwtHelper {
  /// Dekodiert JWT und gibt Payload zurück (ohne Signatur-Prüfung)
  ///
  /// WICHTIG: Verwendet verify=false da wir den Secret-Key nicht haben
  /// Das ist OK, da der Token von Neon Auth kommt und wir ihm vertrauen
  static Map<String, dynamic>? decodeToken(String token) {
    try {
      // JWT dekodieren OHNE Verifikation (wir haben den Secret nicht)
      final jwt = JWT.decode(token);
      return jwt.payload as Map<String, dynamic>?;
    } catch (e) {
      appLogger.e('❌ Fehler beim Dekodieren des JWT: $e');
      return null;
    }
  }
  
  /// Extrahiert User-ID aus JWT
  /// 
  /// Neon Auth JWT enthält: { "sub": "user-uuid", ... }
  static String? extractUserId(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;

    // Versuche verschiedene Standard-Claims
    // 'sub' (Subject) ist der Standard für User-ID
    final userId = payload['sub'] ?? payload['user_id'] ?? payload['id'];

    if (userId != null) {
      appLogger.i('🔑 User-ID aus JWT: $userId');
      return userId.toString();
    }

    appLogger.w('⚠️ Keine User-ID im JWT gefunden');
    appLogger.d('   JWT Payload Keys: ${payload.keys.toList()}');
    return null;
  }
  
  /// Extrahiert Email aus JWT
  static String? extractEmail(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;
    
    final email = payload['email'] ?? payload['user_email'];
    return email?.toString();
  }
  
  /// Extrahiert Name aus JWT (falls vorhanden)
  static String? extractName(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;
    
    final name = payload['name'] ?? payload['full_name'] ?? payload['display_name'];
    return name?.toString();
  }
  
  /// Prüft ob Token abgelaufen ist
  /// 
  /// Returns true wenn Token abgelaufen, false sonst
  static bool isTokenExpired(String token) {
    final payload = decodeToken(token);
    if (payload == null) return true;
    
    final exp = payload['exp'];
    if (exp == null) return false; // Kein Expiration = nie abgelaufen
    
    final expirationDate = DateTime.fromMillisecondsSinceEpoch(
      (exp as int) * 1000, // exp ist in Sekunden, nicht Millisekunden
      isUtc: true,
    );
    
    return DateTime.now().toUtc().isAfter(expirationDate);
  }
  
  /// Holt Expiration-Datum aus JWT
  /// 
  /// Returns null wenn kein exp-Claim vorhanden
  static DateTime? getExpirationDate(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;
    
    final exp = payload['exp'];
    if (exp == null) return null;
    
    return DateTime.fromMillisecondsSinceEpoch(
      (exp as int) * 1000,
      isUtc: true,
    );
  }
  
  /// Alias für getExpirationDate (kürzerer Name)
  static DateTime? getExpiry(String token) {
    return getExpirationDate(token);
  }
  
  /// Gibt vollständigen Token-Payload zurück
  /// 
  /// Alias für decodeToken (besserer Name für Tests)
  static Map<String, dynamic>? getTokenPayload(String token) {
    return decodeToken(token);
  }
  
  /// Prüft ob Token abgelaufen ist
  static bool isExpired(String token) {
    final payload = decodeToken(token);
    if (payload == null) return true;
    
    final exp = payload['exp'];
    if (exp == null) return false; // Kein Ablaufdatum = nie abgelaufen
    
    final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().isAfter(expirationDate);
  }
  
  /// Extrahiert den `role`-Claim aus dem JWT (für Premium-Feature-Gates).
  ///
  /// Neon Auth Custom Claims: `{ "role": "community" | "free" | "basic" | "pro" }`
  /// Gibt `"free"` zurück wenn kein Claim vorhanden.
  static String extractRole(String token) {
    final payload = decodeToken(token);
    if (payload == null) return 'free';
    return payload['role'] as String? ?? 'free';
  }

  /// Debug: Zeige alle Claims im JWT
  static void debugToken(String token) {
    appLogger.d('🔍 JWT Debug:');
    final payload = decodeToken(token);

    if (payload != null) {
      appLogger.d('   Claims:');
      payload.forEach((key, value) {
        appLogger.d('     $key: $value');
      });
    } else {
      appLogger.e('   ❌ Token konnte nicht dekodiert werden');
    }
  }
}
