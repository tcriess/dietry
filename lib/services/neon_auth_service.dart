import 'dart:convert';
import 'dart:math' show min;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
        debugPrint('❌ JWT kann nicht dekodiert werden - invalider Token');
        _refreshAttempts++;
        
        // ✅ Endlosschleifen-Protection
        if (_refreshAttempts >= _maxRefreshAttempts) {
          debugPrint('❌ Maximale Refresh-Versuche erreicht ($_maxRefreshAttempts) - Logout erforderlich');
          await signOut();
          return;
        }
        
        // Warte kurz vor erneutem Versuch (Exponential Backoff)
        await Future.delayed(Duration(seconds: _refreshAttempts * 2));
        
        debugPrint('⚠️ JWT invalide - versuche Refresh (Versuch $_refreshAttempts/$_maxRefreshAttempts)...');
        await refreshToken();
        return;
      }
      
      // Reset Retry-Counter bei erfolgreichem Dekodieren
      _refreshAttempts = 0;
      
      // Prüfe Expiration
      final isExpired = JwtHelper.isExpired(_jwt!);

      if (isExpired) {
        debugPrint('⚠️ JWT ist abgelaufen - versuche mit Retry zu refreshen...');
        // Retry bei Startup: Netzwerk kann kurzzeitig unavailable sein
        final success = await refreshTokenWithRetry(maxAttempts: 3);
        if (!success) {
          debugPrint('❌ Token-Refresh nach Startup fehlgeschlagen - Logout erforderlich');
          await signOut();
        }
      } else {
        // Prüfe wann Token abläuft
        if (payload['exp'] != null) {
          final exp = payload['exp'] as int;
          final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          final timeUntilExpiry = expirationDate.difference(DateTime.now());
          
          debugPrint('⏰ JWT läuft ab in: ${timeUntilExpiry.inMinutes} Minuten');
          
          // Starte Timer für automatisches Refresh (5 Minuten vor Ablauf)
          _scheduleTokenRefresh(timeUntilExpiry);
        }
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Token-Check: $e');
      _refreshAttempts++;
      
      // ✅ Endlosschleifen-Protection
      if (_refreshAttempts >= _maxRefreshAttempts) {
        debugPrint('❌ Maximale Fehler erreicht - Logout erforderlich');
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
    
    debugPrint('🔄 Token-Refresh geplant in: ${delay.inMinutes} Minuten');
    
    _refreshTimer = Timer(delay, () async {
      debugPrint('🔄 Automatisches Token-Refresh...');
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
      debugPrint('🔄 Token refresh attempt $attempt/$maxAttempts...');

      final success = await refreshToken();
      if (success) {
        return true;
      }

      // Retry nur wenn noch Versuche übrig
      if (attempt < maxAttempts) {
        // Exponential backoff: 2s, 4s, 8s
        final delaySeconds = 1 << attempt;
        final delay = Duration(seconds: delaySeconds);
        debugPrint('⏱️ Waiting ${delay.inSeconds}s before retry...');
        await Future.delayed(delay);
      }
    }

    debugPrint('❌ Token refresh failed after $maxAttempts attempts');
    return false;
  }

  /// Refresht das JWT-Token
  Future<bool> refreshToken() async {
    try {
      debugPrint('🔄 Refreshe JWT-Token...');
      
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

      debugPrint('📥 Refresh response: ${response.statusCode} body: ${response.body.length > 80 ? response.body.substring(0, 80) : response.body}');

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
              debugPrint('🍪 Cookie aktualisiert (Native)');
            }
          }
          
          // ✅ JWT extrahieren aus set-auth-jwt Header (NICHT aus session.token!)
          _jwt = response.headers['set-auth-jwt'];
          
          if (_jwt == null || _jwt!.isEmpty) {
            debugPrint('⚠️ Kein JWT im set-auth-jwt Header - versuche session.token');
            // Fallback: session.token
            final sessionData = data['session'] as Map<String, dynamic>?;
            _jwt = sessionData?['token'] as String?;
          }
          
          if (_jwt == null || _jwt!.isEmpty) {
            debugPrint('⚠️ Kein JWT gefunden - versuche /token endpoint');
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
              debugPrint('⚠️ JWT konnte nicht dekodiert werden - kein Refresh geplant');
            }
          }
          
          notifyListeners();
          
          debugPrint('✅ Token erfolgreich refreshed');
          return true;
        }
      } else if (response.statusCode == 401) {
        // Session abgelaufen - User muss neu einloggen
        debugPrint('❌ Session abgelaufen - Logout erforderlich');
        await signOut();
        return false;
      }

      // 200 mit null-Body oder anderer Status: Session nicht verfügbar
      debugPrint('⚠️ Token-Refresh: keine Session (Status ${response.statusCode}, Body leer/null)');
      return false;
      
    } catch (e) {
      debugPrint('❌ Fehler beim Token-Refresh: $e');
      return false;
    }
  }
  
  /// Setzt JWT manuell (z.B. nach Web-Login via auth_callback.html)
  /// 
  /// Wird verwendet wenn JWT bereits aus localStorage geladen wurde
  Future<void> setJWT(String jwt) async {
    try {
      print('🔑 Setze JWT im AuthService...');
      
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
      
      print('✅ JWT im AuthService gesetzt');
    } catch (e) {
      print('❌ Fehler beim Setzen des JWT: $e');
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

      debugPrint('📦 Loaded from storage: JWT=${_jwt != null}, Session=${_session != null}');
    } catch (e) {
      debugPrint('⚠️ Error loading from storage — clearing to prevent repeat failures: $e');
      // Bei Fehler (z.B. korruptem Keystore): Alles löschen damit nächster Start sauber ist
      try {
        await _storage.deleteAll();
        debugPrint('✅ Storage cleared after error');
      } catch (_) {
        // Fehler beim Löschen ignorieren — nächster Start ist eh kaputt
      }
    }
  }
  
  /// Speichert Session in SecureStorage
  Future<void> _saveToStorage() async {
    try {
      if (_session != null) {
        await _storage.write(key: _sessionKey, value: jsonEncode(_session));
      } else {
        await _storage.delete(key: _sessionKey);
      }
      
      if (_jwt != null) {
        await _storage.write(key: _jwtKey, value: _jwt);
      } else {
        await _storage.delete(key: _jwtKey);
      }
      
      if (_cookie != null) {
        await _storage.write(key: _cookieKey, value: _cookie);
      }
      
      debugPrint('💾 Saved to storage: JWT=${_jwt != null}, Session=${_session != null}');
    } catch (e) {
      debugPrint('⚠️ Error saving to storage: $e');
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
      debugPrint('🚀 Starting OAuth flow: provider=$provider, callback=$callbackUrl');
      
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
      
      debugPrint('📥 OAuth response: ${response.statusCode}');
      debugPrint('   Response headers: ${response.headers}');
      debugPrint('   Origin used: $origin');
      
      // Challenge-Cookie separat speichern (wird NICHT vom Token-Refresh überschrieben!)
      // WICHTIG: Der Server sendet das neon_auth_session_challange Cookie (Server-Tippfehler!)
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        final cookies = _parseCookies(setCookie);
        if (cookies.isNotEmpty) {
          // Separater Key: Token-Refresh schreibt nur in _cookieKey, nicht hier!
          await _storage.write(key: _challengeCookieKey, value: cookies);
          debugPrint('🍪 Challenge-Cookie gespeichert: ${cookies.substring(0, min(100, cookies.length))}...');
        } else {
          debugPrint('⚠️ No challenge cookie found in response!');
        }
      } else {
        debugPrint('⚠️ No Set-Cookie header in OAuth response!');
      }
      
      if (response.statusCode != 200) {
        throw Exception('OAuth start failed: ${response.statusCode} - ${response.body}');
      }
      
      final data = jsonDecode(response.body);
      final url = data['url'] as String?;
      
      if (url == null) {
        throw Exception('No OAuth URL in response: $data');
      }
      
      debugPrint('✅ OAuth URL: $url');
      return url;
      
    } catch (e) {
      debugPrint('❌ Error starting OAuth: $e');
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
      final verifierPreview = verifier.length > 20 ? verifier.substring(0, 20) : verifier;
      debugPrint('🔑 Getting session with verifier: $verifierPreview...');
      
      // Native: Challenge-Cookie aus separatem Key laden (nie vom Token-Refresh überschrieben)
      // Web: Browser sendet Cookies automatisch
      String? cookieToSend;
      if (!kIsWeb) {
        final challengeCookie = await _storage.read(key: _challengeCookieKey);
        cookieToSend = challengeCookie ?? _cookie;

        final preview = cookieToSend != null
            ? cookieToSend.substring(0, min(100, cookieToSend.length))
            : 'NONE';
        debugPrint('📱 Native-Plattform: Challenge-Cookie = $preview...');

        if (cookieToSend == null) {
          debugPrint('❌ ERROR: No challenge cookie found! OAuth flow incomplete.');
          return false;
        }
      }

      // Sende Request mit Challenge-Cookie
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session?neon_auth_session_verifier=$verifier'),
        headers: {
          if (!kIsWeb && cookieToSend != null) 'Cookie': cookieToSend,
          'Accept': 'application/json',
        },
      );

      // Challenge-Cookie nach Verwendung löschen (einmalig gültig)
      if (!kIsWeb) {
        await _storage.delete(key: _challengeCookieKey);
      }

      debugPrint('📥 Session response: ${response.statusCode}');
      debugPrint('   Headers: ${response.headers}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Get session failed: ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body);

      if (data == null) {
        debugPrint('⚠️ Session response is null - not authenticated');
        return false;
      }

      // Session-Cookie (für zukünftige Token-Refreshes) aktualisieren
      if (!kIsWeb) {
        final newCookie = response.headers['set-cookie'];
        if (newCookie != null) {
          _cookie = newCookie;
          await _storage.write(key: _cookieKey, value: _cookie);
          debugPrint('🍪 Session-Cookie aktualisiert (Native)');
        }
      }
      
      // Session-Daten enthalten user + session
      _session = data;
      
      // ✅ JWT extrahieren aus set-auth-jwt Header (NICHT aus session.token!)
      // session.token ist nur die Session-ID, NICHT der JWT!
      _jwt = response.headers['set-auth-jwt'];
      
      if (_jwt == null || _jwt!.isEmpty) {
        debugPrint('⚠️ Kein JWT im set-auth-jwt Header - versuche session.token');
        // Fallback: Versuche session.token (für alte API-Versionen)
        final sessionData = data['session'] as Map<String, dynamic>?;
        _jwt = sessionData?['token'] as String?;
      }
      
      if (_jwt == null || _jwt!.isEmpty) {
        debugPrint('⚠️ Kein JWT gefunden - trying /token endpoint');
        await _fetchJWT();
      }
      
      await _saveToStorage();
      notifyListeners();
      
      // Starte Token-Refresh-Timer (nur wenn JWT gültig ist)
      if (_jwt != null && !JwtHelper.isExpired(_jwt!)) {
        await _checkAndRefreshToken();
      } else if (_jwt != null) {
        debugPrint('⚠️ JWT ist bereits abgelaufen - kein Timer gestartet');
      }
      
      debugPrint('✅ Session established: user=${data['user']?['email']}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Error getting session with verifier: $e');
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
      
      debugPrint('🔄 Fetching fresh session...');
      
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session'),
        headers: {
          // Native: Sende Cookie
          // Web: Browser macht das automatisch
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
        },
      );
      
      debugPrint('📥 Session response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data != null) {
          _session = data;
          
          // ✅ JWT extrahieren aus set-auth-jwt Header (NICHT aus session.token!)
          _jwt = response.headers['set-auth-jwt'];
          
          if (_jwt == null || _jwt!.isEmpty) {
            debugPrint('⚠️ Kein JWT im set-auth-jwt Header - versuche session.token');
            final sessionData = data['session'] as Map<String, dynamic>?;
            _jwt = sessionData?['token'] as String?;
          }
          
          if (_jwt == null || _jwt!.isEmpty) {
            debugPrint('⚠️ Kein JWT gefunden - versuche /token endpoint');
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
      debugPrint('❌ Error getting session: $e');
      return null;
    }
  }
  
  /// Holt JWT vom /token Endpunkt
  Future<void> _fetchJWT() async {
    try {
      debugPrint('🔑 Fetching JWT from /token endpoint...');
      
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
          debugPrint('✅ JWT fetched successfully');
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ Error fetching JWT: $e');
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
    debugPrint('📥 Email sign-in: ${response.statusCode}');
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
    debugPrint('📥 Email sign-up: ${response.statusCode}');
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
    debugPrint('📥 Password reset request: ${response.statusCode}');
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
      debugPrint('🗑️ Deleting Neon Auth user...');
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
        debugPrint('✅ Neon Auth user deleted');
      } else {
        // Log but do not throw — DB data is already gone, local cleanup proceeds.
        debugPrint('⚠️ delete-user ${response.statusCode} (best-effort, continuing): ${response.body}');
      }
    } catch (e) {
      debugPrint('⚠️ delete-user network error (best-effort, continuing): $e');
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
      debugPrint('🚪 Signing out...');
      
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
      debugPrint('⚠️ Error during sign-out: $e');
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

      debugPrint('✅ Signed out locally');
    }
  }
}
