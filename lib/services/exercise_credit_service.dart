import 'package:dio/dio.dart';
import 'app_logger.dart';
import 'neon_database_service.dart';

/// Reads and writes the per-day exercise-credit factor — how much of that day's
/// burn is added to its calorie budget.
///
/// One optional row per day, shaped like `cheat_days`: absent means "no opinion
/// for this day", and the profile default (then 1.0) applies. Clearing the
/// override therefore deletes the row rather than writing 1.0 into it, so a
/// later change to the profile default reaches the day.
class ExerciseCreditService {
  final NeonDatabaseService _db;

  ExerciseCreditService(this._db);

  static String _dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The factor set for [date], or null when the day has no override.
  Future<double?> getFactorForDate(DateTime date) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return null;
    final userId = _db.userId;
    if (userId == null) return null;

    final response = await _db.client
        .from('exercise_credit_days')
        .select('factor')
        .eq('user_id', userId)
        .eq('credit_date', _dateStr(date));

    final rows = response as List;
    if (rows.isEmpty) return null;
    final value = (rows.first as Map<String, dynamic>)['factor'];
    return value == null ? null : (value as num).toDouble();
  }

  /// Sets the factor for [date], or removes the override when [factor] is null.
  Future<void> setFactorForDate(DateTime date, double? factor) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    if (factor == null) {
      final response = await _db.dioClient.delete(
        '/exercise_credit_days'
        '?user_id=eq.$userId&credit_date=eq.${_dateStr(date)}',
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception(
            'Failed to clear the day exercise credit (${response.statusCode})');
      }
      appLogger.i('✅ Tages-Credit-Faktor entfernt (${_dateStr(date)})');
      return;
    }

    // on_conflict must name the (user_id, credit_date) unique constraint —
    // PostgREST would otherwise resolve against the surrogate `id` primary key,
    // which never collides, and the upsert would fail on the real constraint.
    final response = await _db.dioClient.post(
      '/exercise_credit_days?on_conflict=user_id,credit_date',
      data: {
        'user_id': userId,
        'credit_date': _dateStr(date),
        'factor': factor,
      },
      options: Options(headers: {
        'Prefer': 'return=minimal,resolution=merge-duplicates',
      }),
    );

    if (response.statusCode != 201 &&
        response.statusCode != 200 &&
        response.statusCode != 204) {
      throw Exception(
          'Failed to set the day exercise credit (${response.statusCode})');
    }
    appLogger.i('✅ Tages-Credit-Faktor gesetzt (${_dateStr(date)}): $factor');
  }
}
