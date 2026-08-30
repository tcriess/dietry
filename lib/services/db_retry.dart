import 'dart:async';

import 'app_logger.dart';

// Retry policy for Data API calls that a *suspended* database can fail.
//
// Neon scales the compute to zero when idle. The app hydrates the day from its
// local mirror on cold start (see DataStore.loadDay), so little touches the
// server until the user opens the add sheet or searches — which means the
// compute is very often suspended at exactly that moment. The request that
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

/// How long each attempt may take, in order. **Escalating**, and that is the
/// whole point.
///
/// Waking the compute is not the only cost: once it is up, its page cache is
/// empty, so the first `search_food_database` — a similarity scan over the
/// whole table — reads its index from remote storage. That can take longer
/// than a warm query by an order of magnitude.
///
/// The first version of this capped *every* attempt at 4s, which made that
/// case unwinnable: each attempt was killed at the same point and the next one
/// started the same cold query over from the beginning, so the retry budget
/// bought nothing. Searching stayed broken until something else happened to
/// warm the database.
///
/// So: attempt 1 is impatient, because a warm database answers in well under a
/// second and there is no reason to hang on a request that is going nowhere.
/// The last attempt is patient enough to let a genuinely slow cold query
/// finish. A real outage still fails fast — a refused connection or an unknown
/// host returns immediately and never spends its timeout.
const List<Duration> kDbAttemptTimeouts = [
  Duration(seconds: 4),
  Duration(seconds: 10),
  Duration(seconds: 25),
];

/// Delay before each retry — one shorter than [kDbAttemptTimeouts], since the
/// last attempt is not followed by one.
///
/// Short, because the waiting that matters happens inside an attempt now: the
/// resume the app is waiting for is already under way, kicked off by the
/// attempt that just timed out.
const List<Duration> kDbRetryBackoff = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
];

/// Runs [operation] against the Data API, retrying transient failures.
///
/// Attempt _n_ is capped at `attemptTimeouts[n]`; failures are retried after
/// `backoff[n]`. The last failure is rethrown, so callers decide whether to
/// surface it — the point of this helper is that a failure stays
/// *distinguishable* from an empty result rather than being flattened into one.
///
/// [onRetry] fires before each retry with the 1-based number of the attempt
/// about to start, so a screen can say that it is waiting on the database
/// rather than leaving a spinner to speak for a wait that can now run to most
/// of a minute.
///
/// Every exception is retried, not just the transport ones. Telling a cold
/// start apart from a genuine client error would mean matching on the postgrest
/// package's exception shape, and getting that match wrong would silently
/// disable the retry for the case it exists for. The budget is bounded, so the
/// cost of retrying an error that was never going to succeed is one budget,
/// once — and an error that fails fast never spends its timeout at all.
///
/// [attemptTimeouts] and [backoff] exist so tests can exercise the policy
/// without spending the real budget on it; production callers use the defaults.
Future<T> withDbRetry<T>(
  Future<T> Function() operation, {
  String label = 'Data API',
  List<Duration> attemptTimeouts = kDbAttemptTimeouts,
  List<Duration> backoff = kDbRetryBackoff,
  void Function(int attempt)? onRetry,
}) async {
  assert(attemptTimeouts.isNotEmpty);
  for (var attempt = 0;; attempt++) {
    try {
      // The last entry also covers any attempt beyond the list, so a caller
      // passing a longer backoff than timeouts still gets a bounded attempt.
      final cap = attempt < attemptTimeouts.length
          ? attemptTimeouts[attempt]
          : attemptTimeouts.last;
      return await operation().timeout(cap);
    } catch (e) {
      if (attempt >= backoff.length) {
        appLogger.e('❌ $label failed after ${attempt + 1} attempts: $e');
        rethrow;
      }
      appLogger.w('⚠️ $label attempt ${attempt + 1} failed ($e) — retrying in '
          '${backoff[attempt].inMilliseconds}ms');
      onRetry?.call(attempt + 2);
      await Future.delayed(backoff[attempt]);
    }
  }
}
