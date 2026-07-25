import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/neon_database_service.dart';

/// Neon's Data API reports authentication problems with **400**, not 401.
/// These payloads are copied verbatim from production responses; if the gateway
/// ever changes its wording, these tests are what will catch it — silently
/// failing to recognise an auth failure puts the app back into the permanent
/// "offline" wedge these strings were added to fix.
Response<dynamic> _response(int status, [Object? body]) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/food_entries'),
      statusCode: status,
      data: body,
    );

void main() {
  group('NeonDatabaseService.isAuthFailureResponse', () {
    test('recognises a missing bearer token (400)', () {
      expect(
        NeonDatabaseService.isAuthFailureResponse(_response(400, {
          'message': 'missing authentication credentials: required '
              'authorization bearer token in JWT format',
        })),
        isTrue,
      );
    });

    test('recognises a malformed token (400)', () {
      expect(
        NeonDatabaseService.isAuthFailureResponse(_response(400, {
          'message': 'Provided authentication token is not a valid JWT encoding',
        })),
        isTrue,
      );
    });

    test('recognises an unverifiable token (400 "jwk not found")', () {
      expect(
        NeonDatabaseService.isAuthFailureResponse(
            _response(400, {'message': 'jwk not found'})),
        isTrue,
      );
    });

    test('still recognises plain 401 and 403', () {
      expect(NeonDatabaseService.isAuthFailureResponse(_response(401)), isTrue);
      expect(NeonDatabaseService.isAuthFailureResponse(_response(403)), isTrue);
    });

    test('a 400 about the data itself is not an auth failure', () {
      // Must stay false: treating it as auth would trigger an endless refresh
      // loop, and the offline queue would keep a hopeless op forever instead of
      // dropping it.
      expect(
        NeonDatabaseService.isAuthFailureResponse(_response(400, {
          'message': 'invalid input syntax for type uuid: ""',
        })),
        isFalse,
      );
      expect(
        NeonDatabaseService.isAuthFailureResponse(_response(400, {
          'message': 'new row violates check constraint '
              '"food_entries_amount_check"',
        })),
        isFalse,
      );
    });

    test('conflicts, server errors and success are not auth failures', () {
      expect(NeonDatabaseService.isAuthFailureResponse(_response(409)), isFalse);
      expect(NeonDatabaseService.isAuthFailureResponse(_response(500)), isFalse);
      expect(NeonDatabaseService.isAuthFailureResponse(_response(200)), isFalse);
    });

    test('a transport failure (no response at all) is not an auth failure', () {
      // This is the genuinely-offline case and must stay distinguishable: it
      // keeps the queued operation, an auth failure does not.
      expect(NeonDatabaseService.isAuthFailureResponse(null), isFalse);
    });

    test('copes with a non-map body', () {
      expect(
        NeonDatabaseService.isAuthFailureResponse(
            _response(400, 'missing authentication credentials')),
        isTrue,
      );
      expect(NeonDatabaseService.isAuthFailureResponse(_response(400)), isFalse);
    });
  });
}
