import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/gear.dart';
import 'app_logger.dart';
import 'neon_database_service.dart';

/// CRUD for the user's gear (running shoes, bikes, …) plus their lifetime
/// usage totals. Mirrors sql/34_gear.sql.
class GearService {
  final NeonDatabaseService _db;

  GearService(this._db);

  String? get _userId => _db.userId;

  Future<List<Gear>> getGear({bool includeRetired = true}) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _userId;
      if (userId == null) return [];

      var query = _db.client.from('gear').select().eq('user_id', userId);
      if (!includeRetired) query = query.eq('retired', false);

      final response = await query.order('name');
      return (response as List)
          .map((json) => Gear.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Ausrüstung: $e');
      return [];
    }
  }

  /// Lifetime distance/time per gear item, keyed by gear id.
  ///
  /// Comes from the `get_gear_totals()` RPC rather than being summed locally:
  /// the offline mirror only holds ~30 days of activities, so a client-side sum
  /// would silently under-report a shoe's lifetime mileage.
  Future<Map<String, GearTotals>> getTotals() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return {};

      // `params: {}` is required even though the function takes no arguments:
      // without it postgrest posts a literal `null` body, which PostgREST
      // rejects with PGRST102 ("invalid type: null, expected a map").
      final response = await _db.client.rpc('get_gear_totals', params: const {});
      final rows = (response as List).cast<Map<String, dynamic>>();
      return {
        for (final row in rows)
          row['gear_id'] as String: GearTotals.fromJson(row),
      };
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Ausrüstungs-Statistik: $e');
      return {};
    }
  }

  Future<Gear> createGear(Gear gear) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID verfügbar');

    final json = gear.toJson();
    json['user_id'] = userId;
    // Client-generated UUID, like activities: the local mirror and the server
    // row must share an id so a write-through cannot fork the record.
    if (json['id'] == null || (json['id'] as String).trim().isEmpty) {
      json['id'] = const Uuid().v4();
    }

    final response = await _db.dioClient.post(
      '/gear',
      data: json,
      options: Options(headers: {'Prefer': 'return=representation'}),
    );

    final rows = response.data as List;
    if (response.statusCode != 201 || rows.isEmpty) {
      throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
    }
    final created = Gear.fromJson(rows.first as Map<String, dynamic>);
    appLogger.i('✅ Ausrüstung erstellt: ${created.name}');
    return created;
  }

  Future<Gear> updateGear(Gear gear) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID verfügbar');

    final json = gear.toJson()..remove('id');
    json['updated_at'] = DateTime.now().toIso8601String();

    final response = await _db.dioClient.patch(
      '/gear?id=eq.${gear.id}&user_id=eq.$userId',
      data: json,
      options: Options(headers: {'Prefer': 'return=representation'}),
    );

    final rows = response.data as List;
    if (response.statusCode != 200 || rows.isEmpty) {
      throw Exception('PATCH fehlgeschlagen: ${response.statusCode}');
    }
    return Gear.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Deletes gear. Activities keep their history — `gear_id` is
  /// `ON DELETE SET NULL`, so the workouts survive, just unattributed.
  /// Prefer retiring over deleting when the user only wants it out of the way.
  Future<void> deleteGear(String id) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID verfügbar');

    final response = await _db.dioClient.delete(
      '/gear?id=eq.$id&user_id=eq.$userId',
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
    }
  }
}
