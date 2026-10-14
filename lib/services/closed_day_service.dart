import 'package:dio/dio.dart';
import 'app_logger.dart';
import 'neon_database_service.dart';

/// Reads and writes `closed_days` — days the user closed, which the app shows
/// read-only until they are reopened. One row per closed day; absent = open.
class ClosedDayService {
  final NeonDatabaseService _db;

  ClosedDayService(this._db);

  static String _dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<bool> isClosed(DateTime date) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return false;
    final userId = _db.userId;
    if (userId == null) return false;

    final response = await _db.client
        .from('closed_days')
        .select('id')
        .eq('user_id', userId)
        .eq('closed_date', _dateStr(date));

    return (response as List).isNotEmpty;
  }

  /// Closes [date], or reopens it when [closed] is false. Both are idempotent.
  Future<void> setClosed(DateTime date, bool closed) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) {
      throw Exception('Token invalid');
    }
    final userId = _db.userId;
    if (userId == null) throw Exception('No user ID');

    if (!closed) {
      final response = await _db.dioClient.delete(
        '/closed_days?user_id=eq.$userId&closed_date=eq.${_dateStr(date)}',
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Failed to reopen day (${response.statusCode})');
      }
      appLogger.i('🔓 Day reopened (${_dateStr(date)})');
      return;
    }

    // on_conflict names the (user_id, closed_date) constraint, so closing an
    // already-closed day is a no-op instead of a 409.
    final response = await _db.dioClient.post(
      '/closed_days?on_conflict=user_id,closed_date',
      data: {'user_id': userId, 'closed_date': _dateStr(date)},
      options: Options(headers: {
        'Prefer': 'return=minimal,resolution=ignore-duplicates',
      }),
    );
    if (response.statusCode != 201 &&
        response.statusCode != 200 &&
        response.statusCode != 204) {
      throw Exception('Failed to close day (${response.statusCode})');
    }
    appLogger.i('🔒 Day closed (${_dateStr(date)})');
  }
}
