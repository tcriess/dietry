// Neon Database Service für Data API Integration
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:postgrest/postgrest.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
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
  
  bool _initialized = false;
  String? _userId;
  String? _jwt;
  
  NeonDatabaseService() {
    _postgrestClient = PostgrestClient(
      dataApiUrl,
      headers: {'Prefer': 'return=representation'},  // ✅ Explizit setzen
    );
  }
  
  /// Initialisiere Dio mit Cookie-Support
  Future<void> init() async {
    if (_initialized) return;
    
    // Cookie-Jar initialisieren (nur für Native)
    if (!kIsWeb) {
      // Native: Persistente Cookies
      final appDocDir = await getApplicationDocumentsDirectory();
      _cookieJar = PersistCookieJar(
        storage: FileStorage('${appDocDir.path}/.cookies/'),
      );
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
        print('🔍 Dio Request: ${options.method} ${options.path}');
        print('🔍 Headers: ${options.headers.keys.where((k) => k != 'Authorization').join(", ")}');
        if (options.headers.containsKey('Authorization')) {
          final auth = options.headers['Authorization'] as String;
          print('🔍 Authorization: ${auth.substring(0, 30)}...');
        }
        print('🔍 Request Data: ${options.data}');
        
        return handler.next(options);
      },
      onError: (error, handler) async {
        // Logge Error-Details
        print('❌ Dio Error: ${error.response?.statusCode}');
        print('   Response Body: ${error.response?.data}');
        print('   Request Path: ${error.requestOptions.path}');
        
        // Bei 401 (Unauthorized) → Token ist abgelaufen, versuche Refresh
        if (error.response?.statusCode == 401 && onTokenExpired != null) {
          print('⚠️ 401 Unauthorized - Token abgelaufen, versuche Refresh...');
          
          try {
            // Refresh Token
            final newToken = await onTokenExpired!();
            
            if (newToken != null) {
              print('✅ Token refreshed, wiederhole Request...');
              
              // Update JWT
              _jwt = newToken;
              
              // Wiederhole Request mit neuem Token
              final options = error.requestOptions;
              options.headers['Authorization'] = 'Bearer $newToken';
              
              final response = await _dio.fetch(options);
              return handler.resolve(response);
            }
          } catch (e) {
            print('❌ Token-Refresh fehlgeschlagen: $e');
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
    
    // Prüfe ob geladener Token noch gültig ist
    if (_jwt != null && JwtHelper.isExpired(_jwt!)) {
      print('⚠️ Geladener JWT-Token ist abgelaufen - refreshe automatisch...');
      
      // Versuche Token zu refreshen wenn onTokenExpired Callback gesetzt ist
      if (onTokenExpired != null) {
        try {
          final newToken = await onTokenExpired!();
          if (newToken != null) {
            _jwt = newToken;
            await _storage.write(key: 'neon_jwt_token', value: _jwt);
            print('✅ JWT-Token erfolgreich refreshed beim Init');
          } else {
            print('❌ Token-Refresh fehlgeschlagen - lösche alten Token');
            _jwt = null;
            await _storage.delete(key: 'neon_jwt_token');
          }
        } catch (e) {
          print('❌ Fehler beim automatischen Token-Refresh: $e');
          _jwt = null;
          await _storage.delete(key: 'neon_jwt_token');
        }
      } else {
        print('⚠️ Kein Token-Refresh-Callback gesetzt - lösche abgelaufenen Token');
        _jwt = null;
        await _storage.delete(key: 'neon_jwt_token');
      }
    }
    
    // Initialisiere PostgrestClient NACH dem Token-Refresh
    final initialHeaders = <String, String>{
      'Prefer': 'return=representation',  // ✅ Explizit setzen um leeren Header zu vermeiden
    };
    if (_jwt != null) {
      initialHeaders['Authorization'] = 'Bearer $_jwt';
      _dio.options.headers['Authorization'] = 'Bearer $_jwt';
      print('🔑 JWT-Token beim Initialisieren geladen: ${_jwt!.substring(0, 20)}...');
    }
    
    _postgrestClient = PostgrestClient(dataApiUrl, headers: initialHeaders);
    
    _initialized = true;
  }
  
  /// Lade gespeicherte Session-Daten (JWT oder User-ID)
  Future<void> _loadSessionData() async {
    _jwt = await _storage.read(key: 'neon_jwt_token');
    _userId = await _storage.read(key: 'neon_user_id');
    
    if (_jwt != null) {
      print('🔑 JWT-Token aus Storage geladen: ${_jwt!.substring(0, 20)}...');
    } else {
      print('⚠️ Kein JWT-Token im Storage gefunden');
    }
  }
  
  /// Setze JWT-Token (falls Better Auth JWT ausgibt)
  Future<void> setJWT(String jwt) async {
    // ✅ WICHTIG: Prüfe ob Token gültig ist BEVOR wir ihn verwenden
    if (JwtHelper.isExpired(jwt)) {
      print('❌ Versuche abgelaufenen Token zu setzen - ABGELEHNT!');
      print('   Token exp: ${JwtHelper.decodeToken(jwt)?['exp']}');
      
      // Versuche Token zu refreshen
      if (onTokenExpired != null) {
        print('🔄 Versuche Token zu refreshen...');
        final newToken = await onTokenExpired!();
        
        if (newToken != null && !JwtHelper.isExpired(newToken)) {
          print('✅ Token erfolgreich refreshed - nutze neuen Token');
          jwt = newToken; // Nutze den neuen Token
        } else {
          print('❌ Token-Refresh fehlgeschlagen - Token wird NICHT gesetzt');
          throw Exception('JWT-Token ist abgelaufen und konnte nicht refreshed werden');
        }
      } else {
        print('❌ Kein Refresh-Callback - Token wird NICHT gesetzt');
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
    
    print('✅ JWT-Token gesetzt und PostgrestClient neu initialisiert');
    
    // Automatisch User in DB anlegen/prüfen
    await _ensureUserExists(jwt);
  }
  
  /// Prüft ob User in DB existiert und legt ihn bei Bedarf an
  Future<void> _ensureUserExists(String jwt) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist (mindestens 5 Min)
      final tokenValid = await ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('❌ Token ungültig - User-Erstellung abgebrochen');
        return;
      }
      
      // Extrahiere User-Info aus aktuellem JWT (könnte refreshed worden sein)
      final userId = JwtHelper.extractUserId(_jwt!);
      final email = JwtHelper.extractEmail(_jwt!);
      final name = JwtHelper.extractName(_jwt!);
      
      if (userId == null) {
        print('⚠️ Keine User-ID im JWT gefunden - User wird nicht in DB angelegt');
        return;
      }
      
      if (email == null) {
        print('⚠️ Keine Email im JWT gefunden - User wird nicht in DB angelegt');
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
      print('❌ Fehler beim Prüfen/Anlegen des Users: $e');
      rethrow;  // Werfe Fehler weiter - muss funktionieren!
    }
  }
  
  /// Setze Session-Token (Verifier vom OAuth-Callback)
  Future<void> setSessionToken(String sessionToken) async {
    await _storage.write(key: 'neon_session_token', value: sessionToken);
    final tokenPreview = sessionToken.length > 20 ? sessionToken.substring(0, 20) : sessionToken;
    print('✅ Session-Token gespeichert: $tokenPreview...');
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
  
  /// Getter für User-ID
  String? get userId => _userId;

  /// Getter für aktuelles JWT (wird von Premium-Features benötigt)
  String? get jwt => _jwt;
  
  /// Prüfe, ob authentifiziert
  bool get isAuthenticated => _jwt != null || _userId != null;
  
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
      print('⚠️ Kein JWT-Token vorhanden');
      return false;
    }
    
    // Prüfe Expiration
    final payload = JwtHelper.decodeToken(_jwt!);
    if (payload == null || payload['exp'] == null) {
      print('⚠️ JWT-Token hat kein Expiration-Datum');
      return false;
    }
    
    final exp = payload['exp'] as int;
    final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final timeUntilExpiry = expirationDate.difference(DateTime.now());
    
    // Token ist bereits abgelaufen
    if (timeUntilExpiry.isNegative) {
      print('❌ JWT-Token ist abgelaufen');
      
      // Versuche Refresh
      if (onTokenExpired != null) {
        print('🔄 Versuche automatischen Token-Refresh...');
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
          
          print('✅ Token erfolgreich refreshed');
          return true;
        } else {
          print('❌ Token-Refresh fehlgeschlagen');
          return false;
        }
      }
      
      return false;
    }
    
    // Token läuft bald ab (< minMinutesValid)
    if (timeUntilExpiry.inMinutes < minMinutesValid) {
      final oldMinutes = timeUntilExpiry.inMinutes;
      print('⚠️ JWT-Token läuft in $oldMinutes Minuten ab - refreshe proaktiv...');
      
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
              print('✅ Token proaktiv refreshed (alt: $oldMinutes Min → neu: ${newTimeUntilExpiry.inMinutes} Min gültig)');
            } else {
              print('✅ Token proaktiv refreshed (alt: $oldMinutes Min → neu: kein Ablaufdatum)');
            }
            return true;
          } else {
            // Callback aufgerufen, aber Refresh fehlgeschlagen (z.B. Session abgelaufen → Logout)
            print('❌ Token-Refresh fehlgeschlagen - Logout wurde ausgelöst');
            return false;
          }
        } catch (e) {
          print('⚠️ Proaktiver Refresh fehlgeschlagen - Token ist aber noch $oldMinutes Min gültig');
          // Token ist noch gültig, auch wenn Refresh fehlschlug
          return true;
        }
      }

      // Kein Callback, aber Token ist noch gültig
      print('⚠️ Token läuft bald ab, aber kein Refresh-Callback verfügbar');
      return true; // Token ist noch gültig
    }
    
    // Token ist noch ausreichend lange gültig
    print('✅ JWT-Token ist noch ${timeUntilExpiry.inMinutes} Minuten gültig');
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
    
    print('🔑 INSERT User mit gültigem JWT: ${_jwt!.substring(0, 20)}...');
    
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
      print('✅ INSERT erfolgreich (Status: ${response.statusCode})');
    } on DioException catch (e) {
      print('❌ INSERT User via Dio fehlgeschlagen:');
      print('   Status: ${e.response?.statusCode}');
      print('   Response Body: ${e.response?.data}');
      print('   Headers: ${e.response?.headers}');
      rethrow;
    } catch (e) {
      print('❌ INSERT User Fehler: $e');
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
      print('❌ UPDATE User via Dio fehlgeschlagen: $e');
      rethrow;
    }
  }
}
