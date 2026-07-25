// Neon Database Service für Data API Integration
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:postgrest/postgrest.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dietry/services/app_logger.dart';
import 'jwt_helper.dart';
import 'user_service.dart';
import 'server_config_service.dart';

class NeonDatabaseService {
  static String get dataApiUrl => ServerConfigService.effectiveDataApiUrl;
  static String get authBaseUrl => ServerConfigService.effectiveAuthBaseUrl;
  
  late PostgrestClient _postgrestClient;
  late Dio _dio;
  CookieJar? _cookieJar;  // Nullable - nur für Native
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  // Callback für Token-Refresh (wird von außen gesetzt)
  Future<String?> Function()? onTokenExpired;

  /// Called when a request failed authentication and [onTokenExpired] could not
  /// obtain a new token — so the session is genuinely dead rather than merely
  /// offline. The UI responds by offering a fresh sign-in.
  void Function()? onAuthRecoveryFailed;

  /// Marker on [RequestOptions.extra]: this request is already the retry that
  /// followed a token refresh and must not trigger a second one.
  static const String _authRetryKey = 'dietry.authRetry';

  bool _initialized = false;
  String? _userId;
  String? _jwt;

  /// True when [response] is the backend saying "the token is missing, broken
  /// or unverifiable".
  ///
  /// Neon's Data API answers all of these with **400**, not 401 — verified
  /// against production:
  ///   no token      → 400 "missing authentication credentials: required
  ///                        authorization bearer token in JWT format"
  ///   garbage token → 400 "Provided authentication token is not a valid JWT encoding"
  ///   foreign key   → 400 "jwk not found"
  ///
  /// While this only checked for 401, the refresh path in the Dio interceptor
  /// was dead code: after an expired token was discarded on startup every
  /// request failed with 400, nothing ever refreshed, and the app hung
  /// permanently in "offline" — across restarts too.
  static bool isAuthFailureResponse(Response? response) {
    final status = response?.statusCode;
    if (status == null) return false;
    if (status == 401 || status == 403) return true;
    if (status != 400) return false;

    final data = response?.data;
    final message = data is Map
        ? (data['message'] ?? data['msg'] ?? '').toString()
        : (data?.toString() ?? '');
    final m = message.toLowerCase();
    return m.contains('authentication') ||
        m.contains('authorization') ||
        m.contains('jwt') ||
        m.contains('jwk') ||
        m.contains('token');
  }

  NeonDatabaseService() {
    _postgrestClient = PostgrestClient(
      dataApiUrl,
      headers: {'Prefer': 'return=representation'},  // ✅ Explizit setzen
    );
  }
  
  /// Initialisiere Dio mit Cookie-Support
  Future<void> init() async {
    if (_initialized) return;
    
    // Cookie-Jar initialisieren (nur für Native).
    // In-memory CookieJar reicht aus — die Datenbank-API authentifiziert per JWT,
    // nicht per Cookie. PersistCookieJar + FileStorage vermieden wegen
    // ClassNotFoundException (io.flutter.util.PathUtils) in Release-Builds.
    if (!kIsWeb) {
      _cookieJar = CookieJar();
    }
    
    _dio = Dio(BaseOptions(
      baseUrl: dataApiUrl,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Interceptor für Authorization-Header + Debug-Logging
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Füge Authorization-Header hinzu wenn JWT vorhanden
        if (_jwt != null && !options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $_jwt';
        }
        
        // Debug: Logge Request-Headers
        appLogger.d('🔍 Dio Request: ${options.method} ${options.path}');
        appLogger.d('🔍 Headers: ${options.headers.keys.where((k) => k != 'Authorization').join(", ")}');
        if (options.headers.containsKey('Authorization')) {
          final auth = options.headers['Authorization'] as String;
          appLogger.d('🔍 Authorization: ${auth.substring(0, 30)}...');
        }
        appLogger.d('🔍 Request Data: ${options.data}');
        
        return handler.next(options);
      },
      onError: (error, handler) async {
        // Logge Error-Details
        appLogger.e('❌ Dio Error: ${error.response?.statusCode}');
        appLogger.e('   Response Body: ${error.response?.data}');
        appLogger.e('   Request Path: ${error.requestOptions.path}');

        // Auth failure (401 OR Neon's 400 variants) → refresh the token.
        // _authRetryKey prevents an endless loop: the retried request passes
        // through this interceptor again and would otherwise refresh once more.
        if (isAuthFailureResponse(error.response) &&
            onTokenExpired != null &&
            error.requestOptions.extra[_authRetryKey] != true) {
          appLogger.w(
              '⚠️ Auth failure (${error.response?.statusCode}) — token expired, attempting refresh...');

          try {
            // Refresh Token
            final newToken = await onTokenExpired!();

            if (newToken == null) {
              // The refresh cannot obtain a token any more. Without this signal
              // the app would stay "logged in" on a stored user id while every
              // request fails — precisely the state that could only be escaped
              // by clearing the app's data.
              appLogger.w('⚠️ Token refresh produced no token — treating session as expired');
              onAuthRecoveryFailed?.call();
            }

            if (newToken != null) {
              appLogger.i('✅ Token refreshed, wiederhole Request...');

              // Update JWT — and keep BOTH clients' auth in lockstep. The
              // PostgrestClient (_db.client) carries a snapshot Authorization
              // header, not the per-request injection the Dio interceptor does.
              // Every other refresh path recreates it with the fresh token, but
              // this 401 path did not — so after a rotation every _db.client
              // read/write kept sending the expired token, RLS answered with
              // zero rows, and reports/services silently showed "no data".
              _jwt = newToken;
              _dio.options.headers['Authorization'] = 'Bearer $newToken';
              _postgrestClient.headers['Authorization'] = 'Bearer $newToken';

              // Wiederhole Request mit neuem Token
              final options = error.requestOptions;
              options.headers['Authorization'] = 'Bearer $newToken';
              options.extra[_authRetryKey] = true;

              final response = await _dio.fetch(options);
              return handler.resolve(response);
            }
          } catch (e) {
            appLogger.e('❌ Token-Refresh fehlgeschlagen: $e');
          }
        }

        return handler.next(error);
      },
    ));
    
    // CookieManager nur für Native hinzufügen
    // Im Web verwaltet der Browser Cookies automatisch
    if (!kIsWeb && _cookieJar != null) {
      _dio.interceptors.add(CookieManager(_cookieJar!));
    }
    
    // Versuche, gespeicherte Session-Daten zu laden
    await _loadSessionData();
    
    // Prüfe ob geladener Token noch gültig ist.
    // Abgelaufene Tokens werden verworfen — kein Netzwerkaufruf während init(),
    // um ein Hängen zu vermeiden. Der Interceptor behandelt 401-Fehler bei
    // echten Requests und löst dort ggf. einen Token-Refresh aus.
    if (_jwt != null && JwtHelper.isExpired(_jwt!)) {
      appLogger.w('⚠️ Geladener JWT-Token ist abgelaufen — wird verworfen');
      _jwt = null;
      await _storage.delete(key: 'neon_jwt_token');
    }
    
    // Initialisiere PostgrestClient NACH dem Token-Refresh
    final initialHeaders = <String, String>{
      'Prefer': 'return=representation',  // ✅ Explizit setzen um leeren Header zu vermeiden
    };
    if (_jwt != null) {
      initialHeaders['Authorization'] = 'Bearer $_jwt';
      _dio.options.headers['Authorization'] = 'Bearer $_jwt';
      appLogger.i('🔑 JWT-Token beim Initialisieren geladen: ${_jwt!.substring(0, 20)}...');
    }

    _postgrestClient = PostgrestClient(dataApiUrl, headers: initialHeaders);

    _initialized = true;
  }

  /// Lade gespeicherte Session-Daten (JWT oder User-ID)
  Future<void> _loadSessionData() async {
    _jwt = await _storage.read(key: 'neon_jwt_token');
    _userId = await _storage.read(key: 'neon_user_id');

    if (_jwt != null) {
      appLogger.i('🔑 JWT-Token aus Storage geladen: ${_jwt!.substring(0, 20)}...');
    } else {
      appLogger.w('⚠️ Kein JWT-Token im Storage gefunden');
    }
  }
  
  /// Setze JWT-Token (falls Better Auth JWT ausgibt)
  Future<void> setJWT(String jwt) async {
    // ✅ WICHTIG: Prüfe ob Token gültig ist BEVOR wir ihn verwenden
    if (JwtHelper.isExpired(jwt)) {
      appLogger.e('❌ Versuche abgelaufenen Token zu setzen - ABGELEHNT!');
      appLogger.e('   Token exp: ${JwtHelper.decodeToken(jwt)?['exp']}');

      // Versuche Token zu refreshen
      if (onTokenExpired != null) {
        appLogger.i('🔄 Versuche Token zu refreshen...');
        final newToken = await onTokenExpired!();

        if (newToken != null && !JwtHelper.isExpired(newToken)) {
          appLogger.i('✅ Token erfolgreich refreshed - nutze neuen Token');
          jwt = newToken; // Nutze den neuen Token
        } else {
          appLogger.e('❌ Token-Refresh fehlgeschlagen - Token wird NICHT gesetzt');
          throw Exception('JWT-Token ist abgelaufen und konnte nicht refreshed werden');
        }
      } else {
        appLogger.e('❌ Kein Refresh-Callback - Token wird NICHT gesetzt');
        throw Exception('JWT-Token ist abgelaufen - bitte neu einloggen');
      }
    }

    _jwt = jwt;
    await _storage.write(key: 'neon_jwt_token', value: jwt);

    // Setze Authorization-Header für alle Requests
    _dio.options.headers['Authorization'] = 'Bearer $jwt';

    // ✅ WICHTIG: Erstelle PostgrestClient NEU mit Authorization-Header!
    _postgrestClient = PostgrestClient(
      dataApiUrl,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Prefer': 'return=representation',  // ✅ Explizit setzen
      },
    );

    appLogger.i('✅ JWT-Token gesetzt und PostgrestClient neu initialisiert');
    
    // Automatisch User in DB anlegen/prüfen
    await _ensureUserExists(jwt);
  }
  
  /// Prüft ob User in DB existiert und legt ihn bei Bedarf an
  Future<void> _ensureUserExists(String jwt) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist (mindestens 5 Min)
      final tokenValid = await ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.e('❌ Token ungültig - User-Erstellung abgebrochen');
        return;
      }

      // Extrahiere User-Info aus aktuellem JWT (könnte refreshed worden sein)
      final userId = JwtHelper.extractUserId(_jwt!);
      final email = JwtHelper.extractEmail(_jwt!);
      final name = JwtHelper.extractName(_jwt!);

      if (userId == null) {
        appLogger.w('⚠️ Keine User-ID im JWT gefunden - User wird nicht in DB angelegt');
        return;
      }

      if (email == null) {
        appLogger.w('⚠️ Keine Email im JWT gefunden - User wird nicht in DB angelegt');
        return;
      }
      
      // UserService verwenden
      final userService = UserService(this);
      await userService.ensureUserExists(
        userId: userId,
        email: email,
        name: name,
      );
      
      // Speichere User-ID für spätere Verwendung
      _userId = userId;
      await _storage.write(key: 'neon_user_id', value: userId);

    } catch (e) {
      appLogger.e('❌ Fehler beim Prüfen/Anlegen des Users: $e');
      rethrow;  // Werfe Fehler weiter - muss funktionieren!
    }
  }

  /// Setze Session-Token (Verifier vom OAuth-Callback)
  Future<void> setSessionToken(String sessionToken) async {
    await _storage.write(key: 'neon_session_token', value: sessionToken);
    final tokenPreview = sessionToken.length > 20 ? sessionToken.substring(0, 20) : sessionToken;
    appLogger.i('✅ Session-Token gespeichert: $tokenPreview...');
  }
  
  /// Setze User-ID (falls nur Cookie-basiert ohne JWT)
  Future<void> setUserId(String userId) async {
    _userId = userId;
    await _storage.write(key: 'neon_user_id', value: userId);
    
    // Setze User-ID-Header für RLS
    _dio.options.headers['X-User-ID'] = userId;
    _postgrestClient.headers['X-User-ID'] = userId;
  }
  
  /// Getter für postgrest-Client (mit aktuellen Auth-Headern)
  PostgrestClient get client => _postgrestClient;
  
  /// Getter für dio-Client (mit Cookie-Support)
  Dio get dioClient => _dio;

  /// Fire-and-forget lightweight authenticated query that wakes a sleeping Neon
  /// serverless compute, so the first real fetch afterwards doesn't pay the
  /// cold-start latency. Best-effort — no await, errors swallowed. HEAD runs
  /// the query on Postgres (passing RLS) but returns no body. Call it as early
  /// as a token is available, e.g. while the UI hydrates from the local cache.
  void warmUp() {
    if (_jwt == null) return;
    try {
      _dio.head('/food_entries', queryParameters: {'limit': 1}).ignore();
    } catch (_) {
      // ignore — warm-up is purely an optimization
    }
  }

  /// Getter für User-ID
  String? get userId => _userId;

  /// Getter für aktuelles JWT (wird von Premium-Features benötigt)
  String? get jwt => _jwt;
  
  /// Prüfe, ob authentifiziert
  bool get isAuthenticated => _jwt != null || _userId != null;

  /// Reachability probe against the Data API. Any HTTP answer — 400 and 404
  /// included — counts as "reachable"; only a transport failure (no DNS, no
  /// route, timeout) means offline.
  ///
  /// Runs on its own Dio without interceptors: the auth interceptor would read
  /// the 400 expected here as an auth failure and kick off a pointless token
  /// refresh.
  Future<bool> ping({Duration timeout = const Duration(seconds: 8)}) async {
    final probe = Dio(BaseOptions(
      baseUrl: dataApiUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
    ));
    try {
      await probe.get('/');
      return true;
    } catch (e) {
      appLogger.d('🔌 Ping failed: $e');
      return false;
    } finally {
      probe.close();
    }
  }

  /// Stellt sicher, dass ein gültiges Token vorhanden ist
  /// 
  /// Prüft ob Token:
  /// - Vorhanden ist
  /// - Noch mindestens 5 Minuten gültig ist
  /// - Falls < 5 Min: Automatischer Refresh
  /// 
  /// Returns: true wenn gültiges Token verfügbar, false sonst
  Future<bool> ensureValidToken({int minMinutesValid = 5}) async {
    // Kein Token vorhanden
    if (_jwt == null) {
      appLogger.w('⚠️ Kein JWT-Token vorhanden');
      return false;
    }

    // Prüfe Expiration
    final payload = JwtHelper.decodeToken(_jwt!);
    if (payload == null || payload['exp'] == null) {
      appLogger.w('⚠️ JWT-Token hat kein Expiration-Datum');
      return false;
    }

    final exp = payload['exp'] as int;
    final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final timeUntilExpiry = expirationDate.difference(DateTime.now());

    // Token ist bereits abgelaufen
    if (timeUntilExpiry.isNegative) {
      appLogger.e('❌ JWT-Token ist abgelaufen');

      // Versuche Refresh
      if (onTokenExpired != null) {
        appLogger.i('🔄 Versuche automatischen Token-Refresh...');
        final newToken = await onTokenExpired!();

        if (newToken != null) {
          _jwt = newToken;
          await _storage.write(key: 'neon_jwt_token', value: _jwt);

          // Update Headers
          _dio.options.headers['Authorization'] = 'Bearer $_jwt';
          _postgrestClient = PostgrestClient(
            dataApiUrl,
            headers: {
              'Authorization': 'Bearer $_jwt',
              'Prefer': 'return=representation',  // ✅ Explizit setzen
            },
          );

          appLogger.i('✅ Token erfolgreich refreshed');
          return true;
        } else {
          appLogger.e('❌ Token-Refresh fehlgeschlagen');
          return false;
        }
      }

      return false;
    }

    // Token läuft bald ab (< minMinutesValid)
    if (timeUntilExpiry.inMinutes < minMinutesValid) {
      final oldMinutes = timeUntilExpiry.inMinutes;
      appLogger.w('⚠️ JWT-Token läuft in $oldMinutes Minuten ab - refreshe proaktiv...');

      // Versuche proaktiven Refresh
      if (onTokenExpired != null) {
        try {
          final newToken = await onTokenExpired!();

          if (newToken != null) {
            _jwt = newToken;
            await _storage.write(key: 'neon_jwt_token', value: _jwt);

            // Update Headers
            _dio.options.headers['Authorization'] = 'Bearer $_jwt';
            _postgrestClient = PostgrestClient(
              dataApiUrl,
              headers: {
                'Authorization': 'Bearer $_jwt',
                'Prefer': 'return=representation',
              },
            );

            // ✅ Berechne neue Ablaufzeit NACH dem Refresh
            final newExpiry = JwtHelper.getExpiry(_jwt!);
            if (newExpiry != null) {
              final newTimeUntilExpiry = newExpiry.difference(DateTime.now());
              appLogger.i('✅ Token proaktiv refreshed (alt: $oldMinutes Min → neu: ${newTimeUntilExpiry.inMinutes} Min gültig)');
            } else {
              appLogger.i('✅ Token proaktiv refreshed (alt: $oldMinutes Min → neu: kein Ablaufdatum)');
            }
            return true;
          } else {
            // Callback aufgerufen, aber Refresh fehlgeschlagen (z.B. Session abgelaufen → Logout)
            appLogger.e('❌ Token-Refresh fehlgeschlagen - Logout wurde ausgelöst');
            return false;
          }
        } catch (e) {
          appLogger.w('⚠️ Proaktiver Refresh fehlgeschlagen - Token ist aber noch $oldMinutes Min gültig');
          // Token ist noch gültig, auch wenn Refresh fehlschlug
          return true;
        }
      }

      // Kein Callback, aber Token ist noch gültig
      appLogger.w('⚠️ Token läuft bald ab, aber kein Refresh-Callback verfügbar');
      return true; // Token ist noch gültig
    }

    // Token ist noch ausreichend lange gültig
    appLogger.i('✅ JWT-Token ist noch ${timeUntilExpiry.inMinutes} Minuten gültig');
    return true;
  }
  
  /// Logout: Lösche Session-Daten
  Future<void> clearSession() async {
    _jwt = null;
    _userId = null;
    await _storage.delete(key: 'neon_jwt_token');
    await _storage.delete(key: 'neon_user_id');
    
    // Lösche Cookies (nur für Native)
    if (_cookieJar != null) {
      await _cookieJar!.deleteAll();
    }
    
    // Entferne Auth-Header
    _dio.options.headers.remove('Authorization');
    _dio.options.headers.remove('X-User-ID');
    
    // Erstelle neuen PostgrestClient ohne Auth-Header
    _postgrestClient = PostgrestClient(
      dataApiUrl,
      headers: {'Prefer': 'return=representation'},  // ✅ Explizit setzen
    );
  }
  
  /// INSERT User direkt via Dio (umgeht postgrest Prefer-Header-Problem)
  Future<void> insertUser({
    required String id,
    required String email,
    String? name,
  }) async {
    // ✅ Stelle sicher dass Token gültig ist
    final tokenValid = await ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) {
      throw Exception('JWT Token ungültig oder abgelaufen - INSERT nicht möglich');
    }
    
    final data = {
      'id': id,
      'email': email,
      if (name != null) 'name': name,
    };
    
    appLogger.i('🔑 INSERT User mit gültigem JWT: ${_jwt!.substring(0, 20)}...');

    try {
      final response = await _dio.post(
        '/users',
        data: data,
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );
      appLogger.i('✅ INSERT erfolgreich (Status: ${response.statusCode})');
    } on DioException catch (e) {
      appLogger.e('❌ INSERT User via Dio fehlgeschlagen:');
      appLogger.e('   Status: ${e.response?.statusCode}');
      appLogger.e('   Response Body: ${e.response?.data}');
      appLogger.e('   Headers: ${e.response?.headers}');
      rethrow;
    } catch (e) {
      appLogger.e('❌ INSERT User Fehler: $e');
      rethrow;
    }
  }

  /// UPDATE User direkt via Dio (umgeht postgrest Prefer-Header-Problem)
  Future<void> updateUserData({
    required String userId,
    required Map<String, dynamic> updates,
  }) async {
    // ✅ Stelle sicher dass Token gültig ist
    final tokenValid = await ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) {
      throw Exception('JWT Token ungültig oder abgelaufen - UPDATE nicht möglich');
    }

    try {
      await _dio.patch(
        '/users?id=eq.$userId',
        data: updates,
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );
    } catch (e) {
      appLogger.e('❌ UPDATE User via Dio fehlgeschlagen: $e');
      rethrow;
    }
  }
}
