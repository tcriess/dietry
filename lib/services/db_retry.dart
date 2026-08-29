import 'dart:async';

import 'app_logger.dart';

// Retry policy for Data API calls that a *suspended* database can fail.
//
// Neon scales the compute to zero when idle. The app hydrates the day from its
// local mirror on cold start (see DataStore.loadDay), so little touches the
// server until the user opens the add sheet or searches — which means the
// compute is very often suspended at exactly that moment. Resuming it usually
// takes well under a second but can run to several, and the request that
// triggers the resume is the one that pays for it.
//
// NeonDatabaseService.warmUp already fires at app start, when the add sheet
// opens and on resume, so the resume is normally under way before the user
// finishes typing. This exists for when it is not: the warm-up is a race, not
// a guarantee, and the user can out-type it.
//
// Neither client sets a transport timeout: PostgrestClient is built with
// package:http's default client and the app's Dio BaseOptions sets none. So
// without withDbRetry a wake-up request either fails fast on a transport error
// or hangs indefinitely — and every caller on this path used to turn that into
// an empty list, which the UI renders identically to "no matches".

/// How long one attempt may take before it is abandoned and retried.
///
/// Deliberately shorter than the total budget: a request stuck on a compute
/// that is still resuming is better cancelled and retried than waited on, and
/// without this there is no timeout on the postgrest path at all.
const Duration kDbAttemptTimeout = Duration(seconds: 4);

/// Delay before each retry. Length + 1 = the number of attempts, so this is
/// four attempts spread over roughly ten seconds of wall clock in the worst
/// case — comfortably longer than a cold start, short enough that a genuine
/// outage still reports back while the user is watching.
const List<Duration> kDbRetryBackoff = [
  Duration(milliseconds: 400),
  Duration(milliseconds: 1200),
  Duration(seconds: 3),
];

/// Runs [operation] against the Data API, retrying transient failures.
///
/// Each attempt is capped at [kDbAttemptTimeout]; failures are retried with
/// [kDbRetryBackoff]. The last failure is rethrown, so callers decide whether
/// to surface it — the point of this helper is that a failure stays
/// *distinguishable* from an empty result rather than being flattened into one.
///
/// Every exception is retried, not just the transport ones. Telling a cold
/// start apart from a genuine client error would mean matching on the postgrest
/// package's exception shape, and getting that match wrong would silently
/// disable the retry for the case it exists for. The budget is bounded, so the
/// cost of retrying an error that was never going to succeed is ~10s, once.
///
/// [attemptTimeout] and [backoff] exist so tests can exercise the policy
/// without spending the real ten seconds on it; production callers use the
/// defaults.
Future<T> withDbRetry<T>(
  Future<T> Function() operation, {
  String label = 'Data API',
  Duration attemptTimeout = kDbAttemptTimeout,
  List<Duration> backoff = kDbRetryBackoff,
}) async {
  for (var attempt = 0;; attempt++) {
    try {
      return await operation().timeout(attemptTimeout);
    } catch (e) {
      if (attempt >= backoff.length) {
        appLogger.e('❌ $label failed after ${attempt + 1} attempts: $e');
        rethrow;
      }
      appLogger.w('⚠️ $label attempt ${attempt + 1} failed ($e) — retrying in '
          '${backoff[attempt].inMilliseconds}ms');
      await Future.delayed(backoff[attempt]);
    }
  }
}
