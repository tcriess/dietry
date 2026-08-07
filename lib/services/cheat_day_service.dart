import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/cheat_day.dart';
import '../models/holiday.dart';
import 'neon_database_service.dart';

class CheatDayService {
  final NeonDatabaseService _db;

  CheatDayService(this._db);

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Returns true if [date] is marked as a cheat day.
  Future<bool> isCheatDay(DateTime date) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return false;
    final userId = _db.userId;
    if (userId == null) return false;

    final dateStr = _dateStr(date);
    final response = await _db.client
        .from('cheat_days')
        .select('id')
        .eq('user_id', userId)
        .eq('cheat_date', dateStr);

    return (response as List).isNotEmpty;
  }

  /// The cheat day row for [date], or null when the day is not marked.
  ///
  /// Carries more than [isCheatDay]: the caller also learns whether the day
  /// belongs to a holiday and under what name, which is what the overview
  /// banner shows.
  Future<CheatDay?> getCheatDay(DateTime date) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return null;
    final userId = _db.userId;
    if (userId == null) return null;

    final response = await _db.client
        .from('cheat_days')
        .select('id,user_id,cheat_date,note,holiday_id,created_at')
        .eq('user_id', userId)
        .eq('cheat_date', _dateStr(date));

    final rows = response as List;
    if (rows.isEmpty) return null;
    return CheatDay.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Marks [date] as a cheat day. No-op if already marked.
  /// Returns the created [CheatDay].
  Future<CheatDay> markCheatDay(DateTime date, {String? note}) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    final payload = {
      'user_id': userId,
      'cheat_date': _dateStr(date),
      if (note != null && note.isNotEmpty) 'note': note,
    };

    // Use Dio directly (consistent with other services that bypass PostgREST quirks)
    final response = await _db.dioClient.post(
      '/cheat_days',
      data: payload,
      options: Options(headers: {'Prefer': 'return=representation'}),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to mark cheat day (${response.statusCode})');
    }

    return CheatDay.fromJson((response.data as List).first as Map<String, dynamic>);
  }

  /// Removes the cheat day mark for [date]. No-op if not marked.
  Future<void> unmarkCheatDay(DateTime date) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    final response = await _db.dioClient.delete(
      '/cheat_days?user_id=eq.$userId&cheat_date=eq.${_dateStr(date)}',
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to unmark cheat day (${response.statusCode})');
    }
  }

  // ── Holidays ───────────────────────────────────────────────────────────────
  //
  // A holiday is a run of ordinary cheat_days rows sharing a holiday_id, not a
  // range row of its own. See sql/migrations/V9__cheat_day_holidays.sql for why.

  /// All declared holidays, newest first. Hand-toggled single days are excluded.
  Future<List<Holiday>> listHolidays() async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return [];
    final userId = _db.userId;
    if (userId == null) return [];

    final response = await _db.client
        .from('cheat_days')
        .select('id,user_id,cheat_date,note,holiday_id,created_at')
        .eq('user_id', userId)
        .not('holiday_id', 'is', null);

    final days = (response as List)
        .map((r) => CheatDay.fromJson(r as Map<String, dynamic>))
        .toList();
    return Holiday.groupFrom(days);
  }

  /// Marks every date from [start] to [end] (inclusive) as a cheat day
  /// belonging to one new holiday. Both dates may be in the future.
  ///
  /// Days already marked are adopted into the holiday rather than rejected, so
  /// declaring a holiday over a day you had toggled by hand does the obvious
  /// thing instead of failing on the (user_id, cheat_date) unique constraint.
  Future<Holiday> createHoliday({
    required DateTime start,
    required DateTime end,
    String? label,
  }) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    final from = _dateOnly(start);
    final to = _dateOnly(end);
    if (to.isBefore(from)) {
      throw ArgumentError('Holiday end date is before its start date');
    }

    final holidayId = const Uuid().v4();
    final trimmed = label?.trim();
    final rows = <Map<String, dynamic>>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      rows.add({
        'id': const Uuid().v4(),
        'user_id': userId,
        'cheat_date': _dateStr(d),
        'holiday_id': holidayId,
        if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
      });
    }

    // on_conflict must name the (user_id, cheat_date) unique constraint —
    // PostgREST would otherwise resolve against the surrogate `id` primary key,
    // which never collides, and the insert would fail on the real constraint.
    final response = await _db.dioClient.post(
      '/cheat_days?on_conflict=user_id,cheat_date',
      data: rows,
      options: Options(headers: {
        'Prefer': 'return=representation,resolution=merge-duplicates',
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to create holiday (${response.statusCode})');
    }

    return Holiday(
      id: holidayId,
      label: (trimmed != null && trimmed.isEmpty) ? null : trimmed,
      start: from,
      end: to,
      dayCount: rows.length,
    );
  }

  /// Deletes a whole holiday, i.e. un-marks every cheat day belonging to it.
  Future<void> deleteHoliday(String holidayId) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    final response = await _db.dioClient.delete(
      '/cheat_days?user_id=eq.$userId&holiday_id=eq.$holidayId',
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete holiday (${response.statusCode})');
    }
  }

  /// Renames a holiday in place. The label is stored on each of its days.
  Future<void> renameHoliday(String holidayId, String? label) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    final trimmed = label?.trim();
    final response = await _db.dioClient.patch(
      '/cheat_days?user_id=eq.$userId&holiday_id=eq.$holidayId',
      data: {'note': (trimmed == null || trimmed.isEmpty) ? null : trimmed},
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to rename holiday (${response.statusCode})');
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Counts cheat days in the current calendar month.
  Future<int> countThisMonth(DateTime month) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return 0;
    final userId = _db.userId;
    if (userId == null) return 0;

    final firstDay = '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final lastDayStr = _dateStr(lastDay);

    final response = await _db.client
        .from('cheat_days')
        .select('id')
        .eq('user_id', userId)
        .gte('cheat_date', firstDay)
        .lte('cheat_date', lastDayStr);

    return (response as List).length;
  }

  /// Computes the current tracking streak.
  ///
  /// A "streak day" is any day on which the user either logged at least one
  /// food entry OR marked the day as a cheat day.
  ///
  /// The streak counts consecutive such days ending today (if today is already
  /// tracked) or yesterday (if today has no tracking yet).
  Future<int> getStreak() async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return 0;
    final userId = _db.userId;
    if (userId == null) return 0;

    final today = DateTime.now();
    final cutoff = _dateStr(today.subtract(const Duration(days: 90)));

    // Distinct dates with food entries
    final entriesResponse = await _db.client
        .from('food_entries')
        .select('entry_date')
        .eq('user_id', userId)
        .gte('entry_date', cutoff);

    // Cheat day dates
    final cheatResponse = await _db.client
        .from('cheat_days')
        .select('cheat_date')
        .eq('user_id', userId)
        .gte('cheat_date', cutoff);

    final trackedDates = <String>{};
    for (final row in (entriesResponse as List)) {
      final d = (row as Map<String, dynamic>)['entry_date'] as String;
      trackedDates.add(d.split('T')[0]);
    }
    for (final row in (cheatResponse as List)) {
      final d = (row as Map<String, dynamic>)['cheat_date'] as String;
      trackedDates.add(d.split('T')[0]);
    }

    return _computeStreak(trackedDates, today);
  }

  int _computeStreak(Set<String> trackedDates, DateTime today) {
    int streak = 0;
    DateTime day = today;

    // If today has no tracking yet, start count from yesterday
    if (!trackedDates.contains(_dateStr(day))) {
      day = day.subtract(const Duration(days: 1));
    }

    for (int i = 0; i < 90; i++) {
      if (trackedDates.contains(_dateStr(day))) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }
}
