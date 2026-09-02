/// Serializes per-day writes of a single value so a burst of taps can never be
/// applied out of order.
///
/// Tapping "+200 ml" twice used to fire two independent upserts — 200, then
/// 400. Nothing keeps two in-flight HTTP requests in order, so the 200 could
/// reach the server last and the day quietly fell back to 200 ml on the next
/// refresh, after having shown 400 ml.
///
/// Here at most one write is in flight at a time. A value submitted while one
/// is running replaces whatever the next write for that day will send, so a
/// burst of taps costs two requests (the one already running plus one final
/// one) and the last value always wins. Days are queued independently: a value
/// for another day never overwrites a pending one, it just waits its turn.
class SerialDayWriter {
  SerialDayWriter({
    required Future<bool> Function(DateTime date, int value) write,
    required void Function(DateTime date, int baseline) onFailure,
  })  : _write = write,
        _onFailure = onFailure;

  /// Persists [value] for [date]. Returns false to trigger [_onFailure].
  final Future<bool> Function(DateTime date, int value) _write;

  /// Called with the value that was displayed before the failed burst started,
  /// so the caller can undo its optimistic update.
  final void Function(DateTime date, int baseline) _onFailure;

  /// Days still to be written, in submission order. `LinkedHashMap` semantics
  /// matter: re-submitting a day keeps its original position in the queue, so
  /// coalescing never reorders days against each other. The entry stays in the
  /// map while its write is in flight — that is what [hasPending] reports.
  final Map<DateTime, _PendingWrite> _queue = {};

  bool _running = false;

  /// Whether a value for [date] has been submitted but not yet acknowledged.
  /// While this is true, a load must not overwrite the in-memory value: the
  /// server has not seen the local change yet, so it would answer with the
  /// value the user just replaced.
  bool hasPending(DateTime date) => _queue.containsKey(_dayOf(date));

  /// Drops everything not yet written. In-flight writes still run to
  /// completion, but their result is no longer applied.
  void clear() => _queue.clear();

  /// Queues [value] for [date] and drains the queue. [baseline] is the value
  /// shown before this change and is only kept for the first submission of a
  /// burst — the one that has to be undone if the burst fails.
  Future<void> submit(DateTime date, int value, {required int baseline}) async {
    final day = _dayOf(date);
    final existing = _queue[day];
    _queue[day] = _PendingWrite(value, existing?.baseline ?? baseline);
    if (_running) return; // the running drain picks the new value up
    _running = true;
    try {
      await _drain();
    } finally {
      _running = false;
    }
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final day = _queue.keys.first;
      final pending = _queue[day]!;
      final ok = await _write(day, pending.value);
      // A newer value arrived while this write ran → keep the entry queued and
      // send that one next. Otherwise the day is done, successfully or not.
      final superseded = _queue[day]?.value != pending.value;
      if (ok && superseded) continue;
      // clear() may have emptied the queue meanwhile; don't resurrect the day.
      final dropped = _queue.remove(day);
      if (!ok && dropped != null) _onFailure(day, pending.baseline);
    }
  }

  static DateTime _dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

class _PendingWrite {
  const _PendingWrite(this.value, this.baseline);

  /// The value to write.
  final int value;

  /// What was displayed before the first change of this burst.
  final int baseline;
}
