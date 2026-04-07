import '../models/user_body_data.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';
import 'app_logger.dart';

/// Service für zeitbasierte Körpermessungen (weight, body_fat, etc.)
class UserBodyMeasurementsService {
  final NeonDatabaseService _db;
  
  UserBodyMeasurementsService(this._db);
  
  String? get _userId => _db.userId;
  
  /// Hole aktuelle Messung
  Future<UserBodyMeasurement?> getCurrentMeasurement() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;
      
      final userId = _userId;
      if (userId == null) return null;
      
      final response = await _db.client
          .from('user_body_measurements')
          .select()
          .eq('user_id', userId)
          .order('measured_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response == null) return null;
      
      return UserBodyMeasurement.fromJson(response);
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Messung: $e');
      return null;
    }
  }

  /// Hole Messung für bestimmtes Datum
  Future<UserBodyMeasurement?> getMeasurementForDate(DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;

      final userId = _userId;
      if (userId == null) return null;

      final dateStr = date.toIso8601String().split('T')[0];

      final response = await _db.client
          .from('user_body_measurements')
          .select()
          .eq('user_id', userId)
          .eq('measured_at', dateStr)
          .maybeSingle();

      if (response == null) return null;

      return UserBodyMeasurement.fromJson(response);
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Messung: $e');
      return null;
    }
  }
  
  /// Speichere Messung (UPSERT via Dio)
  Future<void> saveMeasurement(UserBodyMeasurement measurement) async {
    try {
      appLogger.i('💾 Speichere Messung: ${measurement.weight}kg am ${measurement.measuredAt}');
      
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      final json = measurement.toJson();
      json['user_id'] = userId;
      
      final dateStr = measurement.measuredAt.toIso8601String().split('T')[0];

      // Prüfe ob Entry existiert
      final existing = await _db.client
          .from('user_body_measurements')
          .select()
          .eq('user_id', userId)
          .eq('measured_at', dateStr)
          .maybeSingle();

      if (existing != null) {
        // UPDATE via Dio
        appLogger.d('   📝 Entry existiert - UPDATE via Dio...');
        final response = await _db.dioClient.patch(
          '/user_body_measurements?id=eq.${existing['id']}&user_id=eq.$userId',
          data: json,
          options: Options(
            headers: {
              'Prefer': 'return=minimal',
            },
          ),
        );

        if (response.statusCode != 200 && response.statusCode != 204) {
          throw Exception('UPDATE fehlgeschlagen: ${response.statusCode}');
        }

        appLogger.i('✅ Messung UPDATE erfolgreich');
      } else {
        // INSERT via Dio
        appLogger.d('   ➕ Kein Entry - INSERT via Dio...');
        json.remove('id');

        final response = await _db.dioClient.post(
          '/user_body_measurements',
          data: json,
          options: Options(
            headers: {
              'Prefer': 'return=minimal',
            },
          ),
        );

        if (response.statusCode != 201) {
          throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
        }

        appLogger.i('✅ Messung INSERT erfolgreich');
      }
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern der Messung: $e');
      rethrow;
    }
  }
  
  /// Hole alle Messungen für einen Zeitraum
  Future<List<UserBodyMeasurement>> getMeasurementsInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final startStr = start.toIso8601String().split('T')[0];
      final endStr = end.toIso8601String().split('T')[0];
      
      final response = await _db.client
          .from('user_body_measurements')
          .select()
          .eq('user_id', userId)
          .gte('measured_at', startStr)
          .lte('measured_at', endStr)
          .order('measured_at', ascending: false);
      
      return (response as List)
          .map((item) => UserBodyMeasurement.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Messungen: $e');
      return [];
    }
  }
  
  /// Hole alle Messungen des Users (kein Datumsfilter)
  Future<List<UserBodyMeasurement>> getAllMeasurements() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _userId;
      if (userId == null) return [];
      final response = await _db.client
          .from('user_body_measurements')
          .select()
          .eq('user_id', userId)
          .order('measured_at', ascending: false);
      return (response as List)
          .map((item) => UserBodyMeasurement.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Lösche Messung
  Future<void> deleteMeasurement(String id) async {
    try {
      appLogger.i('🗑️  Lösche Messung: $id');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      appLogger.d('   Führe DELETE via Dio aus...');

      final response = await _db.dioClient.delete(
        '/user_body_measurements?id=eq.$id&user_id=eq.$userId',
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
      }

      appLogger.i('✅ Messung erfolgreich gelöscht');
    } catch (e) {
      appLogger.e('❌ Fehler beim Löschen der Messung: $e');
      rethrow;
    }
  }
}

