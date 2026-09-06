import 'package:dio/dio.dart';
import 'package:dietry/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:postgrest/postgrest.dart' show PostgrestException;

/// The offline banner asks one question: did we reach the server? These tests
/// pin down the answer, because getting it wrong is not a cosmetic bug — the
/// app spent every sync cycle in the red "offline" banner while Neon was
/// answering each request with a perfectly valid 400.
void main() {
  DioException withResponse(int status, [Object? body]) {
    final options = RequestOptions(path: '/physical_activities');
    return DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  group('a server that answers is not an offline server', () {
    test('the check-constraint rejection that started this is not offline', () {
      // Verbatim from the device log: a Health Connect workout whose duration
      // rounds to zero minutes.
      final error = withResponse(400, {
        'code': '23514',
        'message': 'new row for relation "physical_activities" violates '
            'check constraint "physical_activities_duration_minutes_check"',
      });

      expect(classifySyncFailure(error), SyncFailure.rejected);
    });

    test('a rejected write is never queued for a replay that must fail too',
        () {
      // rejected is the one verdict that means "do not queue": replaying it
      // reproduces the same refusal on every cycle.
      expect(classifySyncFailure(withResponse(422)), SyncFailure.rejected);
      expect(classifySyncFailure(withResponse(404)), SyncFailure.rejected);
    });

    test('5xx and 429 are the server stalling, not refusing', () {
      expect(classifySyncFailure(withResponse(500)), SyncFailure.transient);
      expect(classifySyncFailure(withResponse(503)), SyncFailure.transient);
      expect(classifySyncFailure(withResponse(429)), SyncFailure.transient);
    });

    test('an auth rejection is transient — a fresh sign-in replays it', () {
      expect(classifySyncFailure(withResponse(401)), SyncFailure.transient);
      // Neon answers a broken token with 400, not 401.
      expect(
        classifySyncFailure(withResponse(400, {
          'message': 'Provided authentication token is not a valid JWT encoding'
        })),
        SyncFailure.transient,
      );
    });

    test('postgrest builds its exception from a response, so it answered', () {
      expect(
        classifySyncFailure(
            const PostgrestException(message: 'boom', code: '23514')),
        SyncFailure.rejected,
      );
    });
  });

  group('only a transport failure means offline', () {
    test('a request that got no response at all', () {
      expect(
        classifySyncFailure(DioException(
          requestOptions: RequestOptions(path: '/food_entries'),
          type: DioExceptionType.connectionError,
        )),
        SyncFailure.offline,
      );
    });

    test('a connection timeout', () {
      expect(
        classifySyncFailure(DioException(
          requestOptions: RequestOptions(path: '/food_entries'),
          type: DioExceptionType.connectionTimeout,
        )),
        SyncFailure.offline,
      );
    });

    test('postgrest reads travel over package:http, which throws its own', () {
      expect(
        classifySyncFailure(ClientException('Failed host lookup')),
        SyncFailure.offline,
      );
    });
  });

  group('an error that never reached the wire decides nothing', () {
    test('an unusable token must not read as a lost connection', () {
      // FoodEntryService throws this before sending anything. It used to mark
      // the app offline, which is both wrong and unrecoverable: no request
      // goes out, so nothing ever refreshes the token that caused it.
      expect(
        classifySyncFailure(Exception('Token ungültig')),
        SyncFailure.unknown,
      );
    });

    test('an empty PATCH response is a row that is gone, not a dead network',
        () {
      expect(
        classifySyncFailure(
            StateError('UPDATE matched no physical_activities row (id=x)')),
        SyncFailure.unknown,
      );
    });
  });
}
