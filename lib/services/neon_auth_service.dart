import 'dart:convert';
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

/// Neon Auth (Managed Better Auth) client.
///
/// Session: an opaque session cookie (native: stored and sent by hand; web:
/// held by the browser). API access: a short-lived JWT, taken from the
/// `set-auth-jwt` header of `/get-session`, or from `/token` when absent.
///
/// OAuth: `/sign-in/social` sets a one-time challenge cookie, the provider
/// redirects back with `?neon_auth_session_verifier=…`, and `/get-session`
/// with verifier + challenge cookie creates the session.
class NeonAuthService extends ChangeNotifier {
  static String get neonAuthBaseUrl => ServerConfigService.effectiveAuthBaseUrl;

  static const String _sessionKey = 'neon_session';
  static const String _jwtKey = 'neon_jwt';
  static const String _cookieKey = 'neon_cookie';
  // Own key: a token refresh must not overwrite a pending OAuth challenge.
  static const String _challengeCookieKey = 'neon_challenge_cookie';

  /// Refresh this long before the JWT expires.
  static const Duration _refreshLead = Duration(minutes: 1);

  /// Floor for the refresh timer, so a token that arrives nearly expired
  /// (clock skew) cannot spin a refresh loop.
  static const Duration _minRefreshDelay = Duration(seconds: 30);

  final FlutterSecureStorage _storage;
  final http.Client _client;

  String? _jwt;
  Map<String, dynamic>? _session;
  String? _cookie;
  bool _isLoading = true;
  Timer? _refreshTimer;
  Future<bool>? _refreshing;

  String? get jwt => _jwt;
  Map<String, dynamic>? get session => _session;
  bool get isLoggedIn => _jwt != null && _session != null;

  String? get userEmail =>
      (_session?['user'] as Map<String, dynamic>?)?['email'] as String?;
  String? get userName =>
      (_session?['user'] as Map<String, dynamic>?)?['name'] as String?;
  bool get isLoading => _isLoading;

  DateTime? get tokenExpirationDate =>
      _jwt == null ? null : JwtHelper.getExpiry(_jwt!)?.toLocal();

  Duration? get timeUntilTokenExpiry =>
      tokenExpirationDate?.difference(DateTime.now());

  /// Less than 5 minutes left.
  bool get isTokenExpiringSoon {
    final timeLeft = timeUntilTokenExpiry;
    return timeLeft != null && timeLeft.inMinutes < 5;
  }

  /// [client] and [storage] are for tests.
  NeonAuthService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? createAuthHttpClient(),
        _storage = storage ?? const FlutterSecureStorage() {
    _initialized = _initialize();
  }

  /// Completes once the stored session is loaded (and refreshed if expired).
  late final Future<void> _initialized;
  Future<void> get initialized => _initialized;

  Future<void> _initialize() async {
    await _loadFromStorage();
    if (_jwt != null) await _ensureFreshOnStart();
    _isLoading = false;
    notifyListeners();
  }

  /// Startup/setJWT: refresh now if the token is expired or unreadable,
  /// otherwise arm the timer.
  Future<void> _ensureFreshOnStart() async {
    final jwt = _jwt;
    if (jwt == null) return;
    final expiry = JwtHelper.getExpiry(jwt);
    final unreadable = JwtHelper.decodeToken(jwt) == null;
    if (unreadable ||
        (expiry != null &&
            !expiry.isAfter(DateTime.now().toUtc().add(_refreshLead)))) {
      appLogger.d('⚠️ JWT expired or unreadable — refreshing');
      // A failed refresh keeps the session (offline use); refreshToken()
      // signs out itself when the server rejects it.
      await refreshTokenWithRetry(maxAttempts: 3);
      return;
    }
    _armRefreshTimer();
  }

  void _armRefreshTimer() {
    _refreshTimer?.cancel();
    final jwt = _jwt;
    if (jwt == null) return;
    final expiry = JwtHelper.getExpiry(jwt);
    if (expiry == null) return; // no exp claim: never expires
    var delay = expiry.difference(DateTime.now().toUtc()) - _refreshLead;
    if (delay < _minRefreshDelay) delay = _minRefreshDelay;
    appLogger.d('🔄 Token refresh in ${delay.inSeconds}s');
    _refreshTimer = Timer(delay, () => refreshToken());
  }

  /// Retries with backoff (2s, 4s, …) for startup and app resume.
  Future<bool> refreshTokenWithRetry({int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (await refreshToken()) return true;
      if (_jwt == null) return false; // signed out: no point retrying
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    appLogger.d('❌ Token refresh failed after $maxAttempts attempts');
    return false;
  }

  /// Fetches a fresh JWT. Concurrent callers (timer, 401 handler, resume)
  /// share one request.
  Future<bool> refreshToken() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    // If setJWT() lands a fresh login while this is in flight, a stale
    // failure must not sign that new session out.
    final jwtAtStart = _jwt;
    try {
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session'),
        headers: {
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
          // Web: SameSite often blocks the cross-origin cookie; the JWT helps.
          if (jwtAtStart != null) 'Authorization': 'Bearer $jwtAtStart',
          'Accept': 'application/json',
        },
      );

      final data = response.statusCode == 200
          ? _tryDecodeBody(response.body)
          : null;

      // 401, or 200 with an empty body: the server has no session for us.
      if (response.statusCode == 401 ||
          (response.statusCode == 200 && data == null)) {
        if (_jwt != jwtAtStart) return false;
        appLogger.d('❌ Session gone (${response.statusCode}) — signing out');
        await signOut();
        return false;
      }
      if (data == null) {
        appLogger.d('⚠️ Token refresh: status ${response.statusCode}, keeping session');
        return false;
      }

      await _storeSessionCookie(response);
      final newJwt = await _obtainJwt(response);
      if (newJwt == null) {
        appLogger.d('⚠️ Token refresh: no JWT in response, keeping session');
        return false;
      }
      _session = data;
      _jwt = newJwt;
      await _saveToStorage();
      _armRefreshTimer();
      notifyListeners();
      return true;
    } catch (e) {
      appLogger.d('❌ Token refresh error: $e');
      return false;
    }
  }

  /// JWT from the `set-auth-jwt` header, else from `/token`.
  /// Never `session.token`: that is the opaque session token, not a JWT.
  Future<String?> _obtainJwt(http.Response response) async {
    final header = response.headers['set-auth-jwt'];
    if (header != null && header.isNotEmpty) return header;
    return _fetchJwt();
  }

  Future<String?> _fetchJwt() async {
    try {
      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/token'),
        headers: {
          if (!kIsWeb && _cookie != null) 'Cookie': _cookie!,
          if (_jwt != null) 'Authorization': 'Bearer $_jwt',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode != 200) return null;
      final token = _tryDecodeBody(response.body)?['token'];
      return token is String && token.isNotEmpty ? token : null;
    } catch (e) {
      appLogger.d('⚠️ /token failed: $e');
      return null;
    }
  }

  /// Native only: keep the session cookie the server just set.
  Future<void> _storeSessionCookie(http.Response response) async {
    if (kIsWeb) return;
    final cookie = response.headers['set-cookie'];
    if (cookie == null || cookie.isEmpty) return;
    _cookie = cookie;
    await _storage.write(key: _cookieKey, value: cookie);
  }

  /// Sets a JWT obtained elsewhere (web: auth_callback.html via localStorage).
  Future<void> setJWT(String jwt) async {
    final payload = JwtHelper.decodeToken(jwt);
    if (payload == null) throw Exception('JWT kann nicht dekodiert werden');
    if (JwtHelper.isTokenExpired(jwt)) throw Exception('JWT ist bereits abgelaufen');

    _jwt = jwt;
    _session = {
      'user': {
        'id': payload['sub'],
        'email': payload['email'],
        'name': payload['name'],
      },
    };
    await _saveToStorage();
    _armRefreshTimer();
    notifyListeners();
    appLogger.i('✅ JWT im AuthService gesetzt');
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFromStorage() async {
    try {
      final sessionJson = await _storage.read(key: _sessionKey);
      _jwt = await _storage.read(key: _jwtKey);
      _cookie = await _storage.read(key: _cookieKey);
      if (sessionJson != null) _session = jsonDecode(sessionJson);
    } catch (e) {
      appLogger.d('⚠️ Error loading auth state — clearing it: $e');
      _jwt = null;
      _session = null;
      _cookie = null;
      // Not deleteAll(): a running OAuth flow still needs the challenge cookie.
      for (final key in [_sessionKey, _jwtKey, _cookieKey]) {
        try {
          await _storage.delete(key: key);
        } catch (_) {}
      }
    }
  }

  Future<void> _saveToStorage() async {
    try {
      if (_session != null) {
        await _storage.write(key: _sessionKey, value: jsonEncode(_session));
      } else {
        await _storage.delete(key: _sessionKey);
      }
      if (_jwt != null) {
        await _storage.write(key: _jwtKey, value: _jwt!);
      } else {
        await _storage.delete(key: _jwtKey);
      }
      if (_cookie != null) {
        await _storage.write(key: _cookieKey, value: _cookie!);
      }
    } catch (e) {
      appLogger.e('⚠️ Error saving auth state: $e');
      rethrow;
    }
  }

  /// Starts the OAuth flow and returns the provider URL to open.
  Future<String> startOAuthFlow({
    required String provider,
    required String callbackUrl,
  }) async {
    // Origin must match the callback's origin (Neon's trusted-domain check).
    String? origin;
    if (callbackUrl.isNotEmpty) {
      final cb = Uri.parse(callbackUrl);
      final defaultPort = cb.scheme == 'https' ? 443 : 80;
      final port = (cb.hasPort && cb.port != defaultPort) ? ':${cb.port}' : '';
      origin = '${cb.scheme}://${cb.host}$port';
    }

    final response = await _client.post(
      Uri.parse('$neonAuthBaseUrl/sign-in/social'),
      headers: {
        'Content-Type': 'application/json',
        if (origin != null) 'Origin': origin,
        if (_cookie != null) 'Cookie': _cookie!,
      },
      body: jsonEncode({'provider': provider, 'callbackURL': callbackUrl}),
    );

    // The server sets the challenge cookie under both spellings
    // (session_challenge and the legacy session_challange); keep both.
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      final cookies = _parseCookies(setCookie);
      if (cookies.isNotEmpty) {
        await _storage.write(key: _challengeCookieKey, value: cookies);
      }
    }

    if (response.statusCode != 200) {
      throw Exception('OAuth start failed: ${response.statusCode} - ${response.body}');
    }
    final url = _tryDecodeBody(response.body)?['url'] as String?;
    if (url == null) throw Exception('No OAuth URL in response: ${response.body}');
    return url;
  }

  /// Exchanges the OAuth callback's verifier for a session and JWT.
  /// Native sends the stored challenge cookie; web relies on the browser's.
  Future<bool> getSessionWithVerifier(String verifier) async {
    try {
      String? challenge;
      if (!kIsWeb) {
        challenge = await _storage.read(key: _challengeCookieKey) ?? _cookie;
        if (challenge == null) {
          appLogger.e('❌ No challenge cookie — OAuth flow incomplete');
          return false;
        }
      }

      final response = await _client.get(
        Uri.parse('$neonAuthBaseUrl/get-session'
            '?neon_auth_session_verifier=${Uri.encodeQueryComponent(verifier)}'),
        headers: {
          if (challenge != null) 'Cookie': challenge,
          'Accept': 'application/json',
        },
      );

      // The challenge is single-use.
      if (!kIsWeb) {
        try {
          await _storage.delete(key: _challengeCookieKey);
        } catch (_) {}
      }

      if (response.statusCode != 200) {
        throw Exception('Get session failed: ${response.statusCode} - ${response.body}');
      }
      final data = _tryDecodeBody(response.body);
      if (data == null) return false;

      await _storeSessionCookie(response);
      final newJwt = await _obtainJwt(response);
      if (newJwt == null) {
        appLogger.e('❌ Session established but no JWT available');
        return false;
      }
      _session = data;
      _jwt = newJwt;
      await _saveToStorage();
      _armRefreshTimer();
      notifyListeners();
      appLogger.d('✅ Session established: ${data['user']?['email'] ?? 'unknown'}');
      return true;
    } catch (e, stackTrace) {
      appLogger.e('❌ Error getting session with verifier: $e\n$stackTrace');
      return false;
    }
  }

  /// "name=value" pairs from a (comma-joined) Set-Cookie header, attributes
  /// dropped, joined for a Cookie header.
  String _parseCookies(String setCookieHeader) {
    return setCookieHeader
        .split(',')
        .map((part) => part.trim().split(';').first.trim())
        .where((c) => c.isNotEmpty && c.contains('='))
        .join('; ');
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

  /// Sign-in/sign-up response: keep the session cookie and get a JWT.
  /// False when no JWT is issued (sign-up awaiting e-mail verification).
  Future<bool> _handleEmailAuthResponse(http.Response response) async {
    await _storeSessionCookie(response);
    final newJwt = await _obtainJwt(response);
    if (newJwt == null) return false;
    _session = _tryDecodeBody(response.body);
    _jwt = newJwt;
    await _saveToStorage();
    _armRefreshTimer();
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

      appLogger.d('✅ Signed out locally');
    }
  }
}
