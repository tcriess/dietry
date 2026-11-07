import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/neon_auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';

String makeJwt(Duration validFor, {String sub = 'user-1'}) {
  final exp =
      DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
  return JWT({'sub': sub, 'email': 'a@b.c', 'exp': exp})
      .sign(SecretKey('test'));
}

const sessionBody = {
  'session': {'token': 'opaque-session-token'},
  'user': {'id': 'user-1', 'email': 'a@b.c'},
};

/// Records requests; [handler] answers them.
class FakeServer {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) handler;
  FakeServer(this.handler);

  late final client = MockClient((r) {
    requests.add(r);
    return handler(r);
  });

  int count(String path) =>
      requests.where((r) => r.url.path.endsWith(path)).length;
}

http.Response json(Object body, {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

Future<NeonAuthService> loggedIn(FakeServer server, {Duration? validFor}) async {
  FlutterSecureStorage.setMockInitialValues({
    'neon_jwt': makeJwt(validFor ?? const Duration(minutes: 10)),
    'neon_session': jsonEncode(sessionBody),
    'neon_cookie': '__Secure-neon-auth.session_token=s1',
  });
  final auth = NeonAuthService(
      client: server.client, storage: const FlutterSecureStorage());
  await auth.initialized;
  return auth;
}

void main() {
  setUpAll(() => appLogger = Logger(level: Level.off));

  test('refresh takes the JWT from set-auth-jwt and keeps the new cookie',
      () async {
    final fresh = makeJwt(const Duration(minutes: 15));
    final server = FakeServer((r) async => json(sessionBody, headers: {
          'set-auth-jwt': fresh,
          'set-cookie': '__Secure-neon-auth.session_token=s2; Path=/',
        }));
    final auth = await loggedIn(server);

    expect(await auth.refreshToken(), isTrue);
    expect(auth.jwt, fresh);
    expect(server.requests.single.headers['Cookie'],
        '__Secure-neon-auth.session_token=s1');
    expect(server.count('/token'), 0);
    expect(await const FlutterSecureStorage().read(key: 'neon_cookie'),
        contains('s2'));
    auth.dispose();
  });

  test('without the header it asks /token, never uses session.token',
      () async {
    final fromToken = makeJwt(const Duration(minutes: 15));
    final server = FakeServer((r) async => r.url.path.endsWith('/token')
        ? json({'token': fromToken})
        : json(sessionBody));
    final auth = await loggedIn(server);

    expect(await auth.refreshToken(), isTrue);
    expect(auth.jwt, fromToken);
    expect(auth.jwt, isNot('opaque-session-token'));
    auth.dispose();
  });

  test('overlapping refreshes share one request', () async {
    final gate = Completer<void>();
    final server = FakeServer((r) async {
      await gate.future;
      return json(sessionBody,
          headers: {'set-auth-jwt': makeJwt(const Duration(minutes: 15))});
    });
    final auth = await loggedIn(server);

    final a = auth.refreshToken();
    final b = auth.refreshToken();
    gate.complete();
    expect(await Future.wait([a, b]), [true, true]);
    expect(server.count('/get-session'), 1);
    auth.dispose();
  });

  test('401 signs out', () async {
    final server = FakeServer((r) async => r.url.path.endsWith('/sign-out')
        ? json({})
        : json({'message': 'no session'}, status: 401));
    final auth = await loggedIn(server);

    expect(await auth.refreshToken(), isFalse);
    expect(auth.jwt, isNull);
    expect(auth.isLoggedIn, isFalse);
    expect(await const FlutterSecureStorage().read(key: 'neon_jwt'), isNull);
    auth.dispose();
  });

  test('server error or missing JWT keeps the session (offline-safe)',
      () async {
    var status = 503;
    final server = FakeServer((r) async => r.url.path.endsWith('/token')
        ? json({}, status: 500)
        : json(sessionBody, status: status));
    final auth = await loggedIn(server);
    final before = auth.jwt;

    expect(await auth.refreshToken(), isFalse);
    expect(auth.jwt, before);

    status = 200; // session fine, but no JWT obtainable
    expect(await auth.refreshToken(), isFalse);
    expect(auth.jwt, before);
    expect(auth.isLoggedIn, isTrue);
    auth.dispose();
  });

  test('startup refreshes an expired token, leaves a valid one alone',
      () async {
    final fresh = makeJwt(const Duration(minutes: 15));
    final server = FakeServer(
        (r) async => json(sessionBody, headers: {'set-auth-jwt': fresh}));

    final expired = await loggedIn(server, validFor: const Duration(minutes: -5));
    expect(expired.jwt, fresh);
    expect(server.count('/get-session'), 1);
    expired.dispose();

    server.requests.clear();
    final valid = await loggedIn(server, validFor: const Duration(minutes: 10));
    expect(server.requests, isEmpty);
    valid.dispose();
  });

  test('verifier exchange sends the challenge cookie and stores the session',
      () async {
    final jwt = makeJwt(const Duration(minutes: 15));
    final server = FakeServer((r) async => json(sessionBody, headers: {
          'set-auth-jwt': jwt,
          'set-cookie': '__Secure-neon-auth.session_token=s9; Path=/',
        }));
    FlutterSecureStorage.setMockInitialValues({
      'neon_challenge_cookie': '__Secure-neon-auth.session_challenge=c1',
    });
    final auth = NeonAuthService(
        client: server.client, storage: const FlutterSecureStorage());
    await auth.initialized;

    expect(await auth.getSessionWithVerifier('v+1'), isTrue);
    final req = server.requests.single;
    expect(req.url.queryParameters['neon_auth_session_verifier'], 'v+1');
    expect(req.headers['Cookie'], '__Secure-neon-auth.session_challenge=c1');
    expect(auth.jwt, jwt);
    expect(auth.userEmail, 'a@b.c');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'neon_challenge_cookie'), isNull);
    expect(await storage.read(key: 'neon_cookie'), contains('s9'));
    auth.dispose();
  });
}
