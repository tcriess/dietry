import 'dart:convert';
import 'dart:math' show min;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dietry/services/app_logger.dart';
import 'jwt_helper.dart';
import '../app_config.dart';
import 'http_client_factory.dart';
import 'server_config_service.dart';

/// Thrown by [NeonAuthService.signUpWithEmail] when the server accepted the
/// registration but requires the user to verify their e-mail address before
/// a session/JWT is issued.
class EmailVerificationPendingException implements Exception {
  final String email;
  const EmailVerificationPendingException(this.email);
}

/// Neon Auth Service - Implementiert den Better Auth Client Flow
/// 
/// Folgt dem offiziellen Neon Auth Pattern:
/// 1. OAuth redirected zu App mit ?neon_auth_session_verifier=XXX
/// 2. App extrahiert Verifier aus URL
/// 3. /get-session mit Verifier holt Session und JWT
/// 
/// WICHTIG: Der Cookie-Name hat einen Tippfehler!
/// Der Neon Auth Server verwendet: session_challange (mit einem 'l')
/// Nicht session_challenge (mit zwei 'l') - das ist ein bekannter Bug im Server!
class NeonAuthService extends ChangeNotifier {
  static String get neonAuthBaseUrl => ServerConfigService.effectiveAuthBaseUrl;
  
  static const String _sessionKey = 'neon_session';
  static const String _jwtKey = 'neon_jwt';
  static const String _cookieKey = 'neon_cookie';
  // Separater Key für das OAuth Challenge-Cookie (wird von Token-Refresh NICHT überschrieben)
  static const String _challengeCookieKey = 'neon_challenge_cookie';
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client = createAuthHttpClient();
  
  String? _jwt;
  Map<String, dynamic>? _session;
  String? _cookie;
  bool _isLoading = true;
  Timer? _refreshTimer;
  int _refreshAttempts = 0;  // ✅ Endlosschleifen-Protection
  static const int _maxRefreshAttempts = 3;
  
  String? get jwt => _jwt;
  Map<String, dynamic>? get session => _session;
  bool get isLoggedIn => _jwt != null && _session != null;

  String? get userEmail =>
      (_session?['user'] as Map<String, dynamic>?)?['email'] as String?;
  String? get userName =>
      (_session?['user'] as Map<String, dynamic>?)?['name'] as String?;
  bool get isLoading => _isLoading;
  
  /// Gibt zurück wann das Token abläuft (oder null wenn kein Token)
  DateTime? get tokenExpirationDate {
    if (_jwt == null) return null;
    
    final payload = JwtHelper.decodeToken(_jwt!);
    if (payload == null || payload['exp'] == null) return null;
    
    final exp = payload['exp'] as int;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }
  
  /// Gibt zurück wie lange das Token noch gültig ist
  Duration? get timeUntilTokenExpiry {
    final expiration = tokenExpirationDate;
    if (expiration == null) return null;
    
    return expiration.difference(DateTime.now());
  }
  
  /// Prüft ob Token bald abläuft (< 5 Minuten)
  bool get isTokenExpiringSoon {
    final timeLeft = timeUntilTokenExpiry;
    if (timeLeft == null) return false;

    return timeLeft.inMinutes < 5;
  }

  /// Prüft ob Token in weniger als 1 Stunde abläuft (für aggressives Refresh)
  bool get isTokenExpiringWithinHour {
    final timeLeft = timeUntilTokenExpiry;
    if (timeLeft == null) return false;

    return timeLeft.inMinutes < 60;
  }
  
  NeonAuthService() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    await _loadFromStorage();
    
    // Prüfe ob Token noch gültig ist
    if (_jwt != null) {
      await _checkAndRefreshToken();
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Prüft ob Token abgelaufen ist und refresht es bei Bedarf
  Future<void> _checkAndRefreshToken() async {
    if (_jwt == null) return;
    
    try {
      // Prüfe ob Token dekodierbar ist
      final payload = JwtHelper.decodeToken(_jwt!);
      if (payload == null) {
        appLogger.d('❌ JWT kann nicht dekodiert werden - invalider Token');
        _refreshAttempts++;
        
        // ✅ Endlosschleifen-Protection
        if (_refreshAttempts >= _maxRefreshAttempts) {
          appLogger.d('❌ Maximale Refresh-Versuche erreicht ($_maxRefreshAttempts) - Logout erforderlich');
          await signOut();
          return;
        }
        
        // Warte kurz vor erneutem Versuch (Exponential Backoff)
        await Future.delayed(Duration(seconds: _refreshAttempts * 2));
        
        appLogger.d('⚠️ JWT invalide - versuche Refresh (Versuch $_refreshAttempts/$_maxRefreshAttempts)...');
        await refreshToken();
        return;
      }
      
      // Reset Retry-Counter bei erfolgreichem Dekodieren
      _refreshAttempts = 0;
      
      // Prüfe Expiration
      final isExpired = JwtHelper.isExpired(_jwt!);

      if (isExpired) {
        appLogger.d('⚠️ JWT ist abgelaufen - versuche mit Retry zu refreshen...');
        // Retry bei Startup: Netzwerk kann kurzzeitig unavailable sein
        final success = await refreshTokenWithRetry(maxAttempts: 3);
        if (!success) {
          appLogger.d('❌ Token-Refresh nach Startup fehlgeschlagen - Logout erforderlich');
          await signOut();
        }
      } else {
        // Prüfe wann Token abläuft
        if (payload['exp'] != null) {
          final exp = payload['exp'] as int;
          final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          final timeUntilExpiry = expirationDate.difference(DateTime.now());
          
          appLogger.d('⏰ JWT läuft ab in: ${timeUntilExpiry.inMinutes} Minuten');
          
          // Starte Timer für automatisches Refresh (5 Minuten vor Ablauf)
          _scheduleTokenRefresh(timeUntilExpiry);
        }
      }
    } catch (e) {
      appLogger.d('❌ Fehler beim Token-Check: $e');
      _refreshAttempts++;
      
      // ✅ Endlosschleifen-Protection
      if (_refreshAttempts >= _maxRefreshAttempts) {
        appLogger.d('❌ Maximale Fehler erreicht - Logout erforderlich');
        await signOut();
      }
    }
  }
  
  /// Plant automatisches Token-Refresh
  void _scheduleTokenRefresh(Duration timeUntilExpiry) {
    _refreshTimer?.cancel();
    
    // Refresh 5 Minuten vor Ablauf (oder sofort wenn < 5 Min)
    final refreshIn = timeUntilExpiry - const Duration(minutes: 5);
    final delay = refreshIn.isNegative ? Duration.zero : refreshIn;
    
    appLogger.d('🔄 Token-Refresh geplant in: ${delay.inMinutes} Minuten');
    
    _refreshTimer = Timer(delay, () async {
      appLogger.d('🔄 Automatisches Token-Refresh...');
      await refreshToken();
    });
  }
  
  /// Refresht das JWT-Token mit Retry-Logik (für Startup und Resume)
  ///
  /// Bei Fehler wird bis zu maxAttempts mal wiederholt mit exponentieller Backoff.
  /// Dies verbessert die Session-Persistenz nach App-Restart oder bei Netzwerkfehlern.
  Future<bool> refreshTokenWithRetry({int maxAttempts = 3}) async {
    int attempt = 0;

    while (attempt < maxAttempts) {
      attempt++;
      appLogger.d('🔄 Token refresh attempt $attempt/$maxAttempts...');

      final success = await refreshToken();
      if (success) {
        return true;
      }

      // Retry nur wenn noch Versuche übrig
      if (attempt < maxAttempts) {
        // Exponential backoff: 2s, 4s, 8s
        final delaySeconds = 1 << attempt;
        final delay = Duration(seconds: delaySeconds);
        appLogger.d('⏱️ Waiting ${delay.inSeconds}s before retry...');
        await Future.delayed(delay);
      }
    }

    appLogger.d('❌ Token refresh failed after $maxAttempts attempts');
    return false;
  }

  /// Refresht das JWT-Token
  Future<bool> refreshToken() async {
    try {
      appLogger.d('🔄 Refreshe JWT-Token...');
      
      // Hole neue Session vom Server.
      // Native: Cookie manuell mitschicken.
      // Web: Browser-Cookies werden via withCredentials gesendet; zusätzlich
      //      das aktuelle JWT als Bearer-Token, da session-Cookies bei
      //      cross-origin-Requests oft durch SameSite-Policy blockiert werden.
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session'),
        headers: {
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
          if (_jwt != null) 'Authorization': 'Bearer $_jwt',
          'Accept': 'application/json',
        },
      );

      appLogger.d('📥 Refresh response: ${response.statusCode} body: ${response.body.length > 80 ? response.body.substring(0, 80) : response.body}');

      if (response.statusCode == 200) {
        final dynamic decoded = response.body.trim().isEmpty
            ? null
            : jsonDecode(response.body);
        final data = decoded is Map ? decoded as Map<String, dynamic> : null;

        if (data != null) {
          _session = data;
          
          // Update Cookie (nur für Native relevant)
          if (!kIsWeb) {
            final newCookie = response.headers['set-cookie'];
            if (newCookie != null) {
              _cookie = newCookie;
              await _storage.write(key: _cookieKey, value: _cookie);
              appLogger.d('🍪 Cookie aktualisiert (Native)');
            }
          }
          
          // ✅ JWT extrahieren aus set-auth-jwt Header (NICHT aus session.token!)
          _jwt = response.headers['set-auth-jwt'];
          
          if (_jwt == null || _jwt!.isEmpty) {
            appLogger.d('⚠️ Kein JWT im set-auth-jwt Header - versuche session.token');
            // Fallback: session.token
            final sessionData = data['session'] as Map<String, dynamic>?;
            _jwt = sessionData?['token'] as String?;
          }
          
          if (_jwt == null || _jwt!.isEmpty) {
            appLogger.d('⚠️ Kein JWT gefunden - versuche /token endpoint');
            await _fetchJWT();
          } else {
            await _storage.write(key: _jwtKey, value: _jwt);
          }
          
          await _saveToStorage();
          
          // Plane nächstes Refresh (nur wenn JWT gültig dekodierbar ist)
          if (_jwt != null) {
            final payload = JwtHelper.decodeToken(_jwt!);
            if (payload != null) {
              _refreshAttempts = 0; // Reset bei Erfolg
              await _checkAndRefreshToken();
            } else {
              appLogger.d('⚠️ JWT konnte nicht dekodiert werden - kein Refresh geplant');
            }
          }
          
          notifyListeners();
          
          appLogger.d('✅ Token erfolgreich refreshed');
          return true;
        }
      } else if (response.statusCode == 401) {
        // Session abgelaufen - User muss neu einloggen
        appLogger.d('❌ Session abgelaufen - Logout erforderlich');
        await signOut();
        return false;
      }

      // 200 mit null-Body oder anderer Status: Session nicht verfügbar
      appLogger.d('⚠️ Token-Refresh: keine Session (Status ${response.statusCode}, Body leer/null)');
      return false;
      
    } catch (e) {
      appLogger.d('❌ Fehler beim Token-Refresh: $e');
      return false;
    }
  }
  
  /// Setzt JWT manuell (z.B. nach Web-Login via auth_callback.html)
  ///
  /// Wird verwendet wenn JWT bereits aus localStorage geladen wurde
  Future<void> setJWT(String jwt) async {
    try {
      appLogger.i('🔑 Setze JWT im AuthService...');

      // Validiere JWT
      final payload = JwtHelper.decodeToken(jwt);
      if (payload == null) {
        throw Exception('JWT kann nicht dekodiert werden');
      }

      if (JwtHelper.isTokenExpired(jwt)) {
        throw Exception('JWT ist bereits abgelaufen');
      }

      _jwt = jwt;

      // Erstelle minimale Session
      _session = {
        'token': jwt,
        'user': {
          'id': payload['sub'],
          'email': payload['email'],
          'name': payload['name'],
        },
      };

      await _saveToStorage();

      // Plane Token-Refresh
      await _checkAndRefreshToken();

      notifyListeners();

      appLogger.i('✅ JWT im AuthService gesetzt');
    } catch (e) {
      appLogger.e('❌ Fehler beim Setzen des JWT: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  /// Lädt gespeicherte Session aus SecureStorage
  Future<void> _loadFromStorage() async {
    try {
      final sessionJson = await _storage.read(key: _sessionKey);
      final jwt = await _storage.read(key: _jwtKey);
      _cookie = await _storage.read(key: _cookieKey);

      if (sessionJson != null) {
        _session = jsonDecode(sessionJson);
      }
      _jwt = jwt;

      appLogger.d('📦 Loaded from storage: JWT=${_jwt != null}, Session=${_session != null}');
    } catch (e) {
      appLogger.d('⚠️ Error loading from storage — clearing auth state: $e');
      // ✅ WICHTIG: Nur Auth-Keys löschen, NICHT deleteAll()!
      // deleteAll() würde auch den _challengeCookieKey löschen, der gerade für einen
      // laufenden OAuth-Flow benötigt wird (Race Condition: _initialize() läuft parallel
      // zu startOAuthFlow()).
      try { await _storage.delete(key: _sessionKey); } catch (_) {}
      try { await _storage.delete(key: _jwtKey); } catch (_) {}
      try { await _storage.delete(key: _cookieKey); } catch (_) {}
      appLogger.d('✅ Auth state cleared after error (challenge cookie preserved)');
    }
  }
  
  /// Speichert Session in SecureStorage
  Future<void> _saveToStorage() async {
    appLogger.d('[_saveToStorage] Starting save operation');
    try {
      appLogger.d('[_saveToStorage] Saving session data (session=${_session != null})');
      if (_session != null) {
        try {
          final encoded = jsonEncode(_session);
          appLogger.d('[_saveToStorage] ✓ Session JSON encoded (${encoded.length} bytes)');
          await _storage.write(key: _sessionKey, value: encoded);
          appLogger.d('[_saveToStorage] ✓ Session written to storage');
        } catch (e) {
          appLogger.d('[_saveToStorage] ❌ Error saving session: $e');
          rethrow;
        }
      } else {
        appLogger.d('[_saveToStorage] Session is null, deleting from storage');
        await _storage.delete(key: _sessionKey);
        appLogger.d('[_saveToStorage] ✓ Deleted session from storage');
      }

      appLogger.d('[_saveToStorage] Saving JWT (jwt=${_jwt != null ? "SET (${_jwt!.length} bytes)" : "NULL"})');
      if (_jwt != null) {
        try {
          await _storage.write(key: _jwtKey, value: _jwt!);
          appLogger.d('[_saveToStorage] ✓ JWT written to storage');
        } catch (e) {
          appLogger.d('[_saveToStorage] ❌ Error saving JWT: $e');
          rethrow;
        }
      } else {
        appLogger.d('[_saveToStorage] JWT is null, deleting from storage');
        await _storage.delete(key: _jwtKey);
        appLogger.d('[_saveToStorage] ✓ Deleted JWT from storage');
      }

      appLogger.d('[_saveToStorage] Saving cookie (cookie=${_cookie != null ? "SET (${_cookie!.length} bytes)" : "NULL"})');
      if (_cookie != null) {
        try {
          await _storage.write(key: _cookieKey, value: _cookie!);
          appLogger.d('[_saveToStorage] ✓ Cookie written to storage');
        } catch (e) {
          appLogger.d('[_saveToStorage] ❌ Error saving cookie: $e');
          rethrow;
        }
      } else {
        appLogger.d('[_saveToStorage] Cookie is null, skipping');
      }

      appLogger.d('[_saveToStorage] ✅ All data saved successfully');
      appLogger.d('💾 Saved to storage: JWT=${_jwt != null}, Session=${_session != null}');
    } catch (e) {
      appLogger.d('[_saveToStorage] ❌ CRITICAL ERROR in _saveToStorage: $e');
      appLogger.d('[_saveToStorage] ❌ Exception type: ${e.runtimeType}');
      appLogger.e('⚠️ Error saving to storage: $e');
      rethrow;
    }
  }
  
  /// Startet OAuth Flow und gibt die Authorization URL zurück
  /// 
  /// Der Flow:
  /// 1. POST /sign-in/social → Erhalte OAuth URL
  /// 2. User authentifiziert sich beim Provider
  /// 3. OAuth redirected zurück zu callbackUrl mit ?neon_auth_session_verifier=XXX
  Future<String> startOAuthFlow({
    required String provider,
    required String callbackUrl,
  }) async {
    try {
      appLogger.d('🚀 Starting OAuth flow: provider=$provider, callback=$callbackUrl');
      
      // Derive Origin header from the callbackUrl — no hardcoded domains.
      String? origin;
      if (callbackUrl.isNotEmpty) {
        final cbUri = Uri.parse(callbackUrl);
        final defaultPort = cbUri.scheme == 'https' ? 443 : 80;
        final portStr = (cbUri.hasPort && cbUri.port != defaultPort)
            ? ':${cbUri.port}'
            : '';
        origin = '${cbUri.scheme}://${cbUri.host}$portStr';
      }
      
      final response = await _client.post(
        Uri.parse('$neonAuthBaseUrl/sign-in/social'),
        headers: {
          'Content-Type': 'application/json',
          if (origin != null) 'Origin': origin,
          if (_cookie != null) 'Cookie': _cookie!,
        },
        body: jsonEncode({
          'provider': provider,
          'callbackURL': callbackUrl,
        }),
      );
      
      appLogger.d('📥 OAuth response: ${response.statusCode}');
      appLogger.d('   Response headers: ${response.headers}');
      appLogger.d('   Origin used: $origin');
      
      // Challenge-Cookie separat speichern (wird NICHT vom Token-Refresh überschrieben!)
      // WICHTIG: Der Server sendet das neon_auth_session_challange Cookie (Server-Tippfehler!)
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        final cookies = _parseCookies(setCookie);
        if (cookies.isNotEmpty) {
          // Separater Key: Token-Refresh schreibt nur in _cookieKey, nicht hier!
          await _storage.write(key: _challengeCookieKey, value: cookies);
          appLogger.d('🍪 Challenge-Cookie gespeichert: ${cookies.substring(0, min(100, cookies.length))}...');
        } else {
          appLogger.d('⚠️ No challenge cookie found in response!');
        }
      } else {
        appLogger.d('⚠️ No Set-Cookie header in OAuth response!');
      }
      
      if (response.statusCode != 200) {
        throw Exception('OAuth start failed: ${response.statusCode} - ${response.body}');
      }
      
      final data = jsonDecode(response.body);
      final url = data['url'] as String?;
      
      if (url == null) {
        throw Exception('No OAuth URL in response: $data');
      }
      
      appLogger.d('✅ OAuth URL: $url');
      return url;
      
    } catch (e) {
      appLogger.d('❌ Error starting OAuth: $e');
      rethrow;
    }
  }
  
  /// Holt Session mit dem Verifier vom OAuth Callback
  /// 
  /// Nach OAuth Redirect hat die URL: ?neon_auth_session_verifier=XXX
  /// Dieser Verifier wird an /get-session gesendet, um die Session zu erstellen
  /// 
  /// WICHTIG: 
  /// - Native: Der Request MUSS das Challenge-Cookie vom OAuth-Start mitschicken!
  /// - Web: Browser sendet Cookies automatisch
  Future<bool> getSessionWithVerifier(String verifier) async {
    try {
      appLogger.d('🔐 getSessionWithVerifier called with verifier=$verifier');
      final verifierPreview = verifier.length > 20 ? verifier.substring(0, 20) : verifier;
      appLogger.d('🔑 Getting session with verifier: $verifierPreview...');
      appLogger.d('   Reading challenge cookie from storage...');

      // Native: Challenge-Cookie aus separatem Key laden (nie vom Token-Refresh überschrieben)
      // Web: Browser sendet Cookies automatisch
      String? cookieToSend;
      if (!kIsWeb) {
        appLogger.d('   Is native platform');
        final challengeCookie = await _storage.read(key: _challengeCookieKey);
        appLogger.d('   challengeCookie from storage: ${challengeCookie != null ? "SET" : "NULL"}');
        cookieToSend = challengeCookie ?? _cookie;
        appLogger.d('   cookieToSend: ${cookieToSend != null ? "SET" : "NULL"}');

        final preview = cookieToSend != null
            ? cookieToSend.substring(0, min(100, cookieToSend.length))
            : 'NONE';
        appLogger.d('📱 Native-Plattform: Challenge-Cookie = $preview...');

        if (cookieToSend == null) {
          appLogger.d('❌ ERROR: No challenge cookie found! OAuth flow incomplete.');
          appLogger.d('❌ ERROR: No challenge cookie found! OAuth flow incomplete.');
          return false;
        }
      } else {
        appLogger.d('   Is web platform');
      }

      // Sende Request mit Challenge-Cookie
      final requestUrl = '$neonAuthBaseUrl/get-session?neon_auth_session_verifier=$verifier';
      appLogger.d('   📤 Request URL: $requestUrl');
      appLogger.d('   📤 Request headers: Cookie=${cookieToSend != null ? "SET (${cookieToSend.length} bytes)" : "NULL"}');

      final response = await _client.get(
        Uri.parse(requestUrl),
        headers: {
          if (!kIsWeb && cookieToSend != null) 'Cookie': cookieToSend,
          'Accept': 'application/json',
        },
      );
      appLogger.d('   📥 Response status: ${response.statusCode}');
      try {
        appLogger.d('   📥 Getting headers...');
        appLogger.d('   📥 Response headers: ${response.headers}');
      } catch (e) {
        appLogger.d('   ❌ Error printing headers: $e');
      }
      try {
        appLogger.d('   📥 Response body length: ${response.body.length} bytes');
        appLogger.d('   📥 Response body preview: ${response.body.substring(0, min(200, response.body.length))}');
      } catch (e) {
        appLogger.d('   ❌ Error reading response body: $e');
      }

      // [1] Challenge-Cookie löschen (einmalig gültig)
      appLogger.d('[1] 🔑 Deleting challenge cookie after use...');
      try {
        if (!kIsWeb) {
          await _storage.delete(key: _challengeCookieKey);
          appLogger.d('[1] ✓ Challenge cookie deleted from storage');
        }
      } catch (e) {
        appLogger.d('[1] ❌ Error deleting challenge cookie: $e');
        // Continue anyway, this is not critical
      }

      // [2] Status Code Check
      appLogger.d('[2] 📊 Status code: ${response.statusCode}');
      if (response.statusCode != 200) {
        appLogger.d('[2] ❌ Status code is not 200: ${response.statusCode}');
        appLogger.d('[2] ❌ Response body: ${response.body}');
        throw Exception('Get session failed: ${response.statusCode} - ${response.body}');
      }
      appLogger.d('[2] ✓ Status code OK (200)');

      // [3] Log response details
      appLogger.d('[3] 📥 Response headers: ${response.headers.keys.toList()}');
      appLogger.d('[3] 📥 Response body length: ${response.body.length} bytes');
      appLogger.d('[3] 📥 Response body preview: ${response.body.substring(0, min(500, response.body.length))}');

      // [4] Parse JSON response
      appLogger.d('[4] 📦 Parsing JSON response body...');
      dynamic data;
      try {
        data = jsonDecode(response.body);
        appLogger.d('[4] ✓ JSON parsed successfully');
        appLogger.d('[4] ✓ Data type: ${data.runtimeType}');
        if (data is Map<String, dynamic>) {
          appLogger.d('[4] ✓ Top-level keys: ${data.keys.toList()}');
        }
      } catch (e) {
        appLogger.d('[4] ❌ JSON parse error: $e');
        appLogger.d('[4] ❌ Body was: ${response.body}');
        rethrow;
      }

      // [5] Validate parsed data
      appLogger.d('[5] 🔍 Validating parsed data...');
      if (data == null) {
        appLogger.d('[5] ❌ Parsed data is null');
        return false;
      }
      appLogger.d('[5] ✓ Data is not null');

      // [6] Handle set-cookie header (native only)
      appLogger.d('[6] 🍪 Processing session cookie...');
      if (!kIsWeb) {
        try {
          final newCookie = response.headers['set-cookie'];
          appLogger.d('[6] ℹ️  set-cookie header: ${newCookie != null ? "present (${newCookie.length} bytes)" : "MISSING"}');
          if (newCookie != null && newCookie.isNotEmpty) {
            _cookie = newCookie;
            await _storage.write(key: _cookieKey, value: _cookie);
            appLogger.d('[6] ✓ Cookie updated and saved to storage');
          } else {
            appLogger.d('[6] ℹ️  No new cookie, keeping existing');
          }
        } catch (e) {
          appLogger.d('[6] ❌ Error processing cookie: $e');
          // Continue anyway, cookie is not critical
        }
      }

      // [7] Store session data
      appLogger.d('[7] 💾 Storing session data...');
      try {
        _session = data;
        appLogger.d('[7] ✓ Session data stored in memory');
      } catch (e) {
        appLogger.d('[7] ❌ Error storing session: $e');
        rethrow;
      }

      // [8] Extract JWT from set-auth-jwt header
      appLogger.d('[8] 🔑 Extracting JWT from response header...');
      try {
        _jwt = response.headers['set-auth-jwt'];
        if (_jwt != null && _jwt!.isNotEmpty) {
          appLogger.d('[8] ✓ JWT found in set-auth-jwt header');
          appLogger.d('[8] ✓ JWT length: ${_jwt!.length} bytes');
          appLogger.d('[8] ✓ JWT prefix: ${_jwt!.substring(0, min(30, _jwt!.length))}...');
        } else {
          appLogger.d('[8] ℹ️  set-auth-jwt header empty or missing, trying fallback...');
        }
      } catch (e) {
        appLogger.d('[8] ❌ Error reading set-auth-jwt header: $e');
        _jwt = null;
      }

      // [9] Fallback JWT extraction from session.token
      if (_jwt == null || _jwt!.isEmpty) {
        appLogger.d('[9] 🔄 JWT fallback: extracting from session.token...');
        try {
          final sessionData = data['session'] as Map<String, dynamic>?;
          appLogger.d('[9] ℹ️  session field: ${sessionData != null ? "present" : "missing"}');
          if (sessionData != null) {
            appLogger.d('[9] ℹ️  session keys: ${sessionData.keys.toList()}');
            _jwt = sessionData['token'] as String?;
            if (_jwt != null && _jwt!.isNotEmpty) {
              appLogger.d('[9] ✓ JWT extracted from session.token');
              appLogger.d('[9] ✓ JWT length: ${_jwt!.length} bytes');
            } else {
              appLogger.d('[9] ℹ️  session.token is null or empty');
            }
          }
        } catch (e) {
          appLogger.d('[9] ❌ Error extracting from session.token: $e');
          _jwt = null;
        }
      }

      // [10] Third fallback: fetch JWT from /token endpoint
      if (_jwt == null || _jwt!.isEmpty) {
        appLogger.d('[10] 🔄 JWT fallback 2: fetching from /token endpoint...');
        try {
          await _fetchJWT();
          appLogger.d('[10] ✓ _fetchJWT completed');
          if (_jwt != null && _jwt!.isNotEmpty) {
            appLogger.d('[10] ✓ JWT obtained from /token endpoint');
          } else {
            appLogger.d('[10] ❌ _fetchJWT did not set JWT');
          }
        } catch (e) {
          appLogger.d('[10] ❌ Error in _fetchJWT: $e');
        }
      }

      // [11] Final JWT validation
      appLogger.d('[11] 🔑 Final JWT validation...');
      if (_jwt == null || _jwt!.isEmpty) {
        appLogger.d('[11] ❌ CRITICAL: No JWT obtained from any source');
        appLogger.e('❌ No JWT available after all fallbacks');
        return false;
      }
      appLogger.d('[11] ✓ JWT is valid and ready');
      appLogger.d('[11] ✓ JWT length: ${_jwt!.length}');

      // [12] Save all data to persistent storage
      appLogger.d('[12] 💾 Saving authentication data to persistent storage...');
      try {
        await _saveToStorage();
        appLogger.d('[12] ✓ All data saved to storage');
      } catch (e) {
        appLogger.d('[12] ❌ Error saving to storage: $e');
        appLogger.d('[12] ❌ Exception type: ${e.runtimeType}');
        appLogger.d('[12] ❌ Stack trace: $e');
        rethrow;
      }

      // [13] Notify listeners
      appLogger.d('[13] 📢 Notifying listeners of authentication change...');
      try {
        notifyListeners();
        appLogger.d('[13] ✓ Listeners notified successfully');
      } catch (e) {
        appLogger.d('[13] ❌ Error notifying listeners: $e');
        rethrow;
      }

      // [14] Start token refresh timer
      appLogger.d('[14] ⏰ Setting up token refresh timer...');
      try {
        if (_jwt != null && !JwtHelper.isExpired(_jwt!)) {
          appLogger.d('[14] ℹ️  Token not expired, starting refresh timer');
          await _checkAndRefreshToken();
          appLogger.d('[14] ✓ Token refresh timer started');
        } else {
          appLogger.d('[14] ⚠️  Token is expired or null, skipping refresh timer');
        }
      } catch (e) {
        appLogger.d('[14] ⚠️  Error setting up refresh timer: $e');
        // Continue anyway, refresh can happen later
      }

      // [15] Final success log
      appLogger.d('[15] ✅ SUCCESS: Session flow complete');
      final userEmail = data['user']?['email'] ?? 'unknown';
      appLogger.d('[15] ✅ User: $userEmail');
      appLogger.d('[15] ✅ JWT prefix: ${_jwt!.substring(0, min(30, _jwt!.length))}...');
      appLogger.d('✅ Session established: user=$userEmail');
      return true;
      
    } catch (e, stackTrace) {
      appLogger.d('❌ EXCEPTION in getSessionWithVerifier');
      appLogger.d('❌ Exception type: ${e.runtimeType}');
      appLogger.d('❌ Exception message: $e');
      appLogger.d('❌ Stack trace: $stackTrace');
      appLogger.e('❌ Error getting session with verifier: $e\n$stackTrace');
      return false;
    }
  }
  
  /// Holt die aktuelle Session (mit Cache)
  Future<Map<String, dynamic>?> getSession() async {
    try {
      // Nutze gecachte Session falls vorhanden
      if (_session != null) {
        return _session;
      }
      
      appLogger.d('🔄 Fetching fresh session...');
      
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session'),
        headers: {
          // Native: Sende Cookie
          // Web: Browser macht das automatisch
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
        },
      );
      
      appLogger.d('📥 Session response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data != null) {
          _session = data;
          
          // ✅ JWT extrahieren aus set-auth-jwt Header (NICHT aus session.token!)
          _jwt = response.headers['set-auth-jwt'];
          
          if (_jwt == null || _jwt!.isEmpty) {
            appLogger.d('⚠️ Kein JWT im set-auth-jwt Header - versuche session.token');
            final sessionData = data['session'] as Map<String, dynamic>?;
            _jwt = sessionData?['token'] as String?;
          }
          
          if (_jwt == null || _jwt!.isEmpty) {
            appLogger.d('⚠️ Kein JWT gefunden - versuche /token endpoint');
            await _fetchJWT();
          } else {
            await _storage.write(key: _jwtKey, value: _jwt);
          }
          
          await _saveToStorage();
          notifyListeners();
          
          return _session;
        }
      }
      
      return null;
      
    } catch (e) {
      appLogger.d('❌ Error getting session: $e');
      return null;
    }
  }
  
  /// Holt JWT vom /token Endpunkt
  Future<void> _fetchJWT() async {
    try {
      appLogger.d('🔑 Fetching JWT from /token endpoint...');
      
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/token'),
        headers: {
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
          if (_jwt != null) 'Authorization': 'Bearer $_jwt',
          'Accept': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _jwt = data['token'] as String?;
        
        if (_jwt != null) {
          await _storage.write(key: _jwtKey, value: _jwt);
          appLogger.d('✅ JWT fetched successfully');
        }
      }
      
    } catch (e) {
      appLogger.d('⚠️ Error fetching JWT: $e');
    }
  }
  
  /// Parse Set-Cookie header und extrahiere relevante Auth-Cookies
  /// Der Server kann mehrere Cookies senden, wir brauchen das Challenge-Cookie
  String _parseCookies(String setCookieHeader) {
    // Set-Cookie kann mehrere Cookies enthalten (getrennt durch Komma)
    // Beispiel: "cookie1=value1; Path=/; HttpOnly, cookie2=value2; Path=/"
    final cookies = <String>[];
    
    // Einfache Implementierung: Nimm alle Cookie-Werte
    // In Produktion: Parse richtig und filtere nach Namen
    final parts = setCookieHeader.split(',');
    for (final part in parts) {
      final cookiePart = part.trim();
      if (cookiePart.isNotEmpty) {
        // Extrahiere nur "name=value" Teil (ohne Attributes)
        final cookieValue = cookiePart.split(';').first.trim();
        if (cookieValue.isNotEmpty && cookieValue.contains('=')) {
          cookies.add(cookieValue);
        }
      }
    }
    
    // Kombiniere alle Cookies mit "; " (Standard Cookie-Format)
    return cookies.join('; ');
  }
  
  // ── Email / Password Auth ──────────────────────────────────────────────────

  /// Sign in with email and password.
  /// Returns true on success; throws with a user-readable message on failure.
  /// Returns the app origin for email auth requests.
  /// On web: the actual browser origin (works for both localhost and prod).
  /// On native: the configured APP_ORIGIN (used only for the Origin header).
  String? get _emailAuthOrigin {
    if (kIsWeb) return Uri.base.origin;
    final configured = AppConfig.appOrigin;
    return configured.isNotEmpty ? configured : null;
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final origin = _emailAuthOrigin;
    final response = await _client.post(
      Uri.parse('$neonAuthBaseUrl/sign-in/email'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (origin != null) 'Origin': origin,
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    appLogger.d('📥 Email sign-in: ${response.statusCode}');
    if (response.statusCode != 200) {
      final body = _tryDecodeBody(response.body);
      throw Exception(body?['message'] ?? 'Login fehlgeschlagen (${response.statusCode})');
    }
    return await _handleEmailAuthResponse(response);
  }

  /// Register a new account with email and password.
  /// Returns true on success; throws with a user-readable message on failure.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    final origin = _emailAuthOrigin;
    final response = await _client.post(
      Uri.parse('$neonAuthBaseUrl/sign-up/email'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (origin != null) 'Origin': origin,
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': (name != null && name.isNotEmpty) ? name : email.split('@').first,
        if (kIsWeb && origin != null) 'callbackURL': '$origin/',
      }),
    );
    appLogger.d('📥 Email sign-up: ${response.statusCode}');
    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = _tryDecodeBody(response.body);
      throw Exception(body?['message'] ?? 'Registrierung fehlgeschlagen (${response.statusCode})');
    }
    final success = await _handleEmailAuthResponse(response);
    if (!success) {
      // Server accepted the sign-up but issued no JWT — email verification required.
      throw EmailVerificationPendingException(email);
    }
    return true;
  }

  /// Send a password-reset email to [email].
  ///
  /// Neon Auth will e-mail a link pointing to [redirectTo] with a `token`
  /// query-parameter. On web the link points to `/reset_password.html`.
  Future<void> requestPasswordReset(String email) async {
    // On web: derive from the current browser origin.
    // On native: use PASSWORD_RESET_REDIRECT_URL from config.
    final redirectTo = kIsWeb
        ? '${Uri.base.origin}/reset_password.html'
        : AppConfig.passwordResetRedirectUrl;
    // Use the redirectTo URL's own origin as the Origin header so Neon Auth's
    // redirect-URL validation passes (it appears to require Origin == redirectTo origin).
    final resetOrigin = Uri.parse(redirectTo).origin;
    final response = await _client.post(
      Uri.parse('$neonAuthBaseUrl/request-password-reset'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Origin': resetOrigin,
      },
      body: jsonEncode({
        'email': email,
        'redirectTo': redirectTo,
      }),
    );
    appLogger.d('📥 Password reset request: ${response.statusCode}');
    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = _tryDecodeBody(response.body);
      throw Exception(body?['message'] ?? 'Fehler beim Zurücksetzen (${response.statusCode})');
    }
  }

  Future<bool> _handleEmailAuthResponse(http.Response response) async {
    final data = _tryDecodeBody(response.body);

    if (!kIsWeb) {
      final cookie = response.headers['set-cookie'];
      if (cookie != null) {
        _cookie = cookie;
        await _storage.write(key: _cookieKey, value: _cookie);
      }
    }

    _session = data;
    _jwt = response.headers['set-auth-jwt'];

    if (_jwt == null || _jwt!.isEmpty) {
      final sessionData = data?['session'] as Map<String, dynamic>?;
      _jwt = sessionData?['token'] as String?;
    }

    if (_jwt == null || _jwt!.isEmpty) {
      await _fetchJWT();
    }

    if (_jwt == null || _jwt!.isEmpty) return false;

    await _saveToStorage();
    await _checkAndRefreshToken();
    notifyListeners();
    return true;
  }

  Map<String, dynamic>? _tryDecodeBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Löscht den Neon-Auth-Account des eingeloggten Nutzers (best-effort).
  ///
  /// Versucht POST /delete-user. Schlägt der Server-Call fehl (z.B. weil der
  /// Neon-Auth-Managed-Service diesen Endpoint nicht direkt für Clients
  /// freigibt), wird nur gewarnt — die Nutzdaten sind bereits aus PostgREST
  /// gelöscht und der lokale State wird in jedem Fall gecleart.
  Future<void> deleteAuthUser() async {
    try {
      appLogger.d('🗑️ Deleting Neon Auth user...');
      final origin = _emailAuthOrigin;
      final response = await _client.post(
        Uri.parse('$neonAuthBaseUrl/delete-user'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-neon-auth-middleware': 'true',
          if (origin != null) 'Origin': origin,
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
          if (_jwt != null) 'Authorization': 'Bearer $_jwt',
        },
        body: '{}',
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        appLogger.d('✅ Neon Auth user deleted');
      } else {
        // Log but do not throw — DB data is already gone, local cleanup proceeds.
        appLogger.d('⚠️ delete-user ${response.statusCode} (best-effort, continuing): ${response.body}');
      }
    } catch (e) {
      appLogger.d('⚠️ delete-user network error (best-effort, continuing): $e');
    } finally {
      _refreshTimer?.cancel();
      _session = null;
      _jwt = null;
      _cookie = null;
      // ✅ Nur Auth-Keys löschen (NICHT deleteAll()!)
      // deleteAll() würde auch user settings wie water_reminder_enabled löschen
      await _storage.delete(key: _sessionKey);
      await _storage.delete(key: _jwtKey);
      await _storage.delete(key: _cookieKey);
      await _storage.delete(key: _challengeCookieKey);
      notifyListeners();
    }
  }

  /// Logout
  Future<void> signOut() async {
    try {
      appLogger.d('🚪 Signing out...');
      
      // Call server sign-out endpoint
      await _client.post(
        Uri.parse('$neonAuthBaseUrl/sign-out'),
        headers: {
          'Content-Type': 'application/json',
          if (_cookie != null) 'Cookie': _cookie!,
        },
        body: '{}',
      );
      
    } catch (e) {
      appLogger.d('⚠️ Error during sign-out: $e');
    } finally {
      // Clear local state regardless of server response
      _session = null;
      _jwt = null;
      _cookie = null;

      // ✅ Nur Auth-Keys löschen (NICHT deleteAll()!)
      // deleteAll() würde auch user settings wie water_reminder_enabled löschen
      await _storage.delete(key: _sessionKey);
      await _storage.delete(key: _jwtKey);
      await _storage.delete(key: _cookieKey);
      await _storage.delete(key: _challengeCookieKey);

      notifyListeners();

      appLogger.d('✅ Signed out locally');
    }
  }
}
