import 'package:dietry/services/app_logger.dart';
import 'neon_database_service.dart';

class WaterIntakeService {
  final NeonDatabaseService _db;

  WaterIntakeService(this._db);

  String? get _userId => _db.userId;

  /// Returns today's water intake in ml (0 if no entry exists yet).
  Future<int> getIntakeForDate(DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return 0;
      final userId = _userId;
      if (userId == null) return 0;

      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _db.client
          .from('water_intake')
          .select('amount_ml')
          .eq('user_id', userId)
          .eq('date', dateStr)
          .maybeSingle();

      if (response == null) return 0;
      return (response['amount_ml'] as num).toInt();
    } catch (e) {
      appLogger.e('❌ WaterIntakeService.getIntakeForDate: $e');
      return 0;
    }
  }

  /// Upserts the water intake for [date] to [amountMl].
  /// Returns the new amount on success, null on failure.
  Future<int?> setIntakeForDate(DateTime date, int amountMl) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;
      final userId = _userId;
      if (userId == null) return null;

      final dateStr = date.toIso8601String().split('T')[0];
      await _db.client.from('water_intake').upsert(
        {
          'user_id': userId,
          'date': dateStr,
          'amount_ml': amountMl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,date',
      );
      return amountMl;
    } catch (e) {
      appLogger.e('❌ WaterIntakeService.setIntakeForDate: $e');
      return null;
    }
  }
}
