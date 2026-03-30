import 'package:dio/dio.dart';
import '../models/cheat_day.dart';
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
