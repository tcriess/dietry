import 'package:dio/dio.dart';
import 'neon_database_service.dart';
import 'platform_export.dart' as exporter;

/// Account-level operations: data export and full account deletion.
class AccountService {
  final NeonDatabaseService _db;

  AccountService(this._db);

  String? get _userId => _db.userId;

  // ── Data export ────────────────────────────────────────────────────────────

  /// Fetch all user data, write CSV files and share / download them.
  Future<void> exportAndShare() async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in');

    await _db.ensureValidToken(minMinutesValid: 5);

    // Fetch all tables in parallel.
    final results = await Future.wait([
      _db.client.from('food_entries').select().eq('user_id', userId).order('entry_date'),
      _db.client.from('physical_activities').select().eq('user_id', userId).order('start_time'),
      _db.client.from('user_body_measurements').select().eq('user_id', userId).order('measured_at'),
      _db.client.from('nutrition_goals').select().eq('user_id', userId).order('valid_from'),
    ]);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 16);

    final files = <String, String>{
      'dietry_${timestamp}_food_entries.csv': _csv(
        headers: ['date', 'meal_type', 'name', 'amount', 'unit', 'calories_kcal',
                   'protein_g', 'fat_g', 'carbs_g'],
        rows: (results[0] as List).map((e) => [
          e['entry_date'], e['meal_type'], e['name'],
          e['amount'], e['unit'], e['calories'],
          e['protein'], e['fat'], e['carbs'],
        ]).toList(),
      ),
      'dietry_${timestamp}_activities.csv': _csv(
        headers: ['start_time', 'end_time', 'duration_min', 'activity_name',
                   'calories_burned', 'distance_km', 'source'],
        rows: (results[1] as List).map((e) => [
          e['start_time'], e['end_time'], e['duration_minutes'],
          e['activity_name'] ?? e['activity_type'],
          e['calories_burned'], e['distance_km'], e['source'],
        ]).toList(),
      ),
      'dietry_${timestamp}_measurements.csv': _csv(
        headers: ['date', 'weight_kg', 'body_fat_pct', 'muscle_mass_kg', 'waist_cm'],
        rows: (results[2] as List).map((e) => [
          e['measured_at'], e['weight'], e['body_fat_percentage'],
          e['muscle_mass_kg'], e['waist_cm'],
        ]).toList(),
      ),
      'dietry_${timestamp}_goals.csv': _csv(
        headers: ['valid_from', 'calories_kcal', 'protein_g', 'fat_g', 'carbs_g'],
        rows: (results[3] as List).map((e) => [
          e['valid_from'], e['calories'], e['protein'], e['fat'], e['carbs'],
        ]).toList(),
      ),
    };

    await exporter.exportCsvFiles(timestamp: timestamp, files: files);
  }

  // ── Account deletion ───────────────────────────────────────────────────────

  /// Permanently delete all user data from every table.
  /// The caller must sign out afterwards.
  Future<void> deleteAllUserData() async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in');

    await _db.ensureValidToken(minMinutesValid: 5);

    // All child tables have ON DELETE CASCADE, so deleting the users row
    // removes all user data in one shot.
    // Use Dio directly (not the PostgREST client) to avoid the global
    // "Prefer: return=representation" header which PostgREST rejects on DELETE.
    await _db.dioClient.delete(
      '/users?id=eq.$userId',
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _csv({required List<String> headers, required List<List<dynamic>> rows}) {
    final buf = StringBuffer();
    buf.writeln(headers.join(','));
    for (final row in rows) {
      buf.writeln(row.map((v) => _escape(v?.toString() ?? '')).join(','));
    }
    return buf.toString();
  }

  String _escape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
