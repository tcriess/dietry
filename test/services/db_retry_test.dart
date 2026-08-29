import 'dart:async';

import 'package:dietry/services/app_logger.dart';
import 'package:dietry/services/db_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initializeAppLogger);

  // The real policy takes ~10s by design; exercise its shape with a fast one.
  const fastBackoff = [
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
  ];
  const fastTimeout = Duration(milliseconds: 50);

  Future<T> run<T>(Future<T> Function() op) => withDbRetry(
        op,
        attemptTimeout: fastTimeout,
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

  test('the shipped budget outlasts a cold start but still reports back', () {
    final worstCase = kDbRetryBackoff.fold<Duration>(
          Duration.zero,
          (sum, d) => sum + d,
        ) +
        kDbAttemptTimeout * (kDbRetryBackoff.length + 1);
    // Long enough for a Neon resume, short enough that a real outage does not
    // leave the user staring at a spinner.
    expect(worstCase, greaterThan(const Duration(seconds: 8)));
    expect(worstCase, lessThan(const Duration(seconds: 30)));
  });
}
