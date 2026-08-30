import 'dart:async';

import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/db_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initializeAppLogger);

  // The real policy runs to most of a minute by design; exercise its shape
  // with a fast one.
  const fastBackoff = [
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
  ];
  const fastTimeouts = [
    Duration(milliseconds: 20),
    Duration(milliseconds: 40),
    Duration(milliseconds: 60),
    Duration(milliseconds: 80),
  ];

  Future<T> run<T>(Future<T> Function() op) => withDbRetry(
        op,
        attemptTimeouts: fastTimeouts,
        backoff: fastBackoff,
      );

  test('a first-attempt success runs the operation exactly once', () async {
    var calls = 0;
    final result = await run(() async {
      calls++;
      return 'ok';
    });
    expect(result, 'ok');
    expect(calls, 1);
  });

  test('an empty result is an answer, not a failure to retry', () async {
    // The distinction this helper exists to preserve: "no matches" and "could
    // not reach the database" must not collapse into the same thing.
    var calls = 0;
    final result = await run(() async {
      calls++;
      return <String>[];
    });
    expect(result, isEmpty);
    expect(calls, 1);
  });

  test('retries a cold start that succeeds on a later attempt', () async {
    var calls = 0;
    final result = await run(() async {
      calls++;
      if (calls < 3) throw StateError('compute still resuming');
      return 'awake';
    });
    expect(result, 'awake');
    expect(calls, 3);
  });

  test('gives up after the budget and rethrows the last failure', () async {
    var calls = 0;
    await expectLater(
      run(() async {
        calls++;
        throw StateError('still down');
      }),
      throwsA(isA<StateError>()),
    );
    // One attempt per backoff step, plus the initial try.
    expect(calls, fastBackoff.length + 1);
  });

  test('an attempt that hangs is timed out rather than waited on', () async {
    var calls = 0;
    await expectLater(
      run(() async {
        calls++;
        // Never completes: without the per-attempt timeout this would hang the
        // search forever instead of retrying. There is no timeout on the
        // postgrest path itself, which is why this matters. A bare Completer
        // rather than a long delay, so the test leaves no pending timers.
        return Completer<String>().future;
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, fastBackoff.length + 1);
  });

  test('a later attempt is allowed to run longer than an earlier one',
      () async {
    // The regression that made v1.7.0's search still fail: every attempt was
    // capped at the same 4s, so a cold query slower than that was killed at the
    // same point every time and the retries bought nothing. A slow operation
    // must be able to win on a later, more patient attempt.
    var calls = 0;
    final result = await run(() async {
      calls++;
      // Longer than attempts 1 and 2 allow, shorter than attempt 3.
      await Future.delayed(const Duration(milliseconds: 50));
      return 'slow but fine';
    });
    expect(result, 'slow but fine');
    expect(calls, 3,
        reason: 'the first two attempts time out, the third does not');
  });

  test('onRetry announces each retry so the UI can explain the wait', () async {
    final announced = <int>[];
    var calls = 0;
    await withDbRetry(
      () async {
        calls++;
        if (calls < 3) throw StateError('resuming');
        return 'awake';
      },
      attemptTimeouts: fastTimeouts,
      backoff: fastBackoff,
      onRetry: announced.add,
    );
    expect(announced, [2, 3],
        reason: '1-based number of the attempt about to start');
  });

  test('the shipped budget outlasts a cold query but still reports back', () {
    final worstCase = kDbRetryBackoff.fold<Duration>(
          Duration.zero,
          (sum, d) => sum + d,
        ) +
        kDbAttemptTimeouts.fold<Duration>(Duration.zero, (sum, d) => sum + d);
    // Long enough for a resumed-but-cold database to answer a similarity scan,
    // short enough that a real outage still reports back while the user is
    // watching. A refused connection never spends its timeout, so an outage
    // costs a fraction of this.
    expect(worstCase, greaterThan(const Duration(seconds: 30)));
    expect(worstCase, lessThan(const Duration(seconds: 60)));

    // Escalating, not flat — see the regression test above.
    expect(kDbAttemptTimeouts.first, lessThan(kDbAttemptTimeouts.last));
    expect(kDbRetryBackoff.length, kDbAttemptTimeouts.length - 1,
        reason: 'the last attempt is not followed by a retry');
  });
}
