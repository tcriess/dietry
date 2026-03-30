import '../models/user_body_data.dart';
import 'neon_database_service.dart';
import 'nutrition_calculator.dart';
import 'package:dio/dio.dart';

/// Service für User-Körperdaten CRUD-Operationen
class UserBodyDataService {
  final NeonDatabaseService _db;

  UserBodyDataService(this._db);

  String? get _userId => _db.userId;

  /// Hole die aktuellsten Körperdaten des Users
  Future<UserBodyData?> getCurrentBodyData() async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Körperdaten nicht laden');
        return null;
      }

      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar - kann Körperdaten nicht laden');
        return null;
      }

      // Hole aktuellsten Eintrag (nach measured_at sortiert)
      final response = await _db.client
          .from('user_body_data')
          .select()
          .eq('user_id', userId)
          .order('measured_at', ascending: false)
          .limit(1);

      if (response == null || (response as List).isEmpty) {
        print('ℹ️ Keine Körperdaten gefunden');
        return null;
      }

      final data = (response as List).first as Map<String, dynamic>;
      return UserBodyData.fromJson(data);
    } catch (e) {
      print('❌ Fehler beim Abrufen der Körperdaten: $e');
      return null;
    }
  }

  /// Hole alle Körperdaten des Users (für Historie/Tracking)
  Future<List<UserBodyData>> getAllBodyData() async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Körperdaten nicht laden');
        return [];
      }

      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar - kann Körperdaten nicht laden');
        return [];
      }

      // Hole alle Einträge, sortiert nach Datum
      final response = await _db.client
          .from('user_body_data')
          .select()
          .eq('user_id', userId)
          .order('measured_at', ascending: false);

      if (response == null) return [];

      return (response as List)
          .map((item) => UserBodyData.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Fehler beim Abrufen aller Körperdaten: $e');
      return [];
    }
  }

  /// Speichere oder aktualisiere Körperdaten
  /// 
  /// Verwendet UPSERT: Wenn Eintrag für measured_at existiert → UPDATE, sonst INSERT
  Future<void> saveBodyData(
    UserBodyData bodyData, {
    DateTime? measuredAt,
    bool calculateMetrics = true,
  }) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig - kann Körperdaten nicht speichern');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar - kann Körperdaten nicht speichern');
      }

      final json = bodyData.toJson();
      json['user_id'] = userId;
      json['measured_at'] = (measuredAt ?? DateTime.now()).toIso8601String().split('T')[0];

      // Optional: Berechne und speichere Metriken
      if (calculateMetrics) {
        final recommendation = NutritionCalculator.calculateMacros(bodyData);
        json['bmr'] = recommendation.bmr;
        json['tdee'] = recommendation.tdee;
        json['target_calories'] = recommendation.calories;
      }

      print('🔍 Speichere Körperdaten: ${json['weight']}kg, ${json['height']}cm für $userId am ${json['measured_at']}');

      // ✅ Prüfe ob Entry für dieses Datum existiert
      final existing = await _db.client
          .from('user_body_data')
          .select()
          .eq('user_id', userId)
          .eq('measured_at', json['measured_at'])
          .maybeSingle();
      
      if (existing != null) {
        // UPDATE via Dio
        print('   📝 Entry existiert - UPDATE via Dio...');
        final response = await _db.dioClient.patch(
          '/user_body_data?id=eq.${existing['id']}&user_id=eq.$userId',
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
        
        print('✅ Körperdaten UPDATE erfolgreich');
      } else {
        // INSERT via Dio
        print('   ➕ Kein Entry - INSERT via Dio...');
        json.remove('id');  // ID wird von DB generiert
        
        final response = await _db.dioClient.post(
          '/user_body_data',
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
        
        print('✅ Körperdaten INSERT erfolgreich');
      }
    } catch (e) {
      print('❌ Fehler beim Speichern der Körperdaten: $e');
      rethrow;
    }
  }

  /// Aktualisiere statische Profildaten in der users-Tabelle
  Future<void> updateUserProfile(UserProfile profile) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID');

    final response = await _db.dioClient.patch(
      '/users?id=eq.$userId',
      data: profile.toJson(),
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Profil-Update fehlgeschlagen: ${response.statusCode}');
    }
    print('✅ Profil gespeichert');
  }

  /// Speichere neue Körpermessung in user_body_measurements (UPSERT by date)
  Future<void> addMeasurement(UserBodyMeasurement measurement) async {
    final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) throw Exception('Token ungültig');
    final userId = _userId;
    if (userId == null) throw Exception('Keine User-ID');

    final json = measurement.toJson();
    json['user_id'] = userId;
    json.remove('id');

    final response = await _db.dioClient.post(
      '/user_body_measurements',
      data: json,
      options: Options(headers: {
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Messung speichern fehlgeschlagen: ${response.statusCode}');
    }
    print('✅ Messung gespeichert: ${measurement.weight}kg');
  }

  /// Lösche Körperdaten-Eintrag
  Future<void> deleteBodyData(String id) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig - kann Körperdaten nicht löschen');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar - kann Körperdaten nicht löschen');
      }

      await _db.client
          .from('user_body_data')
          .delete()
          .eq('id', id)
          .eq('user_id', userId); // RLS-safe: nur eigene Daten

      print('✅ Körperdaten gelöscht: $id');
    } catch (e) {
      print('❌ Fehler beim Löschen der Körperdaten: $e');
      rethrow;
    }
  }

  /// Hole Körperdaten für ein bestimmtes Datum
  Future<UserBodyData?> getBodyDataForDate(DateTime date) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Körperdaten nicht laden');
        return null;
      }

      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar');
        return null;
      }

      final dateStr = date.toIso8601String().split('T')[0];

      final response = await _db.client
          .from('user_body_data')
          .select()
          .eq('user_id', userId)
          .eq('measured_at', dateStr)
          .single();

      return UserBodyData.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Fehler beim Abrufen der Körperdaten für $date: $e');
      return null;
    }
  }

  /// Hole Gewichtsverlauf (für Charts/Tracking)
  Future<List<Map<String, dynamic>>> getWeightHistory({int? limitDays}) async {
    try {
      // ✅ Stelle sicher dass Token gültig ist
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig - kann Gewichtsverlauf nicht laden');
        return [];
      }

      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar');
        return [];
      }

      var query = _db.client
          .from('user_body_data')
          .select('measured_at, weight, bmr, tdee')
          .eq('user_id', userId)
          .order('measured_at', ascending: false);

      if (limitDays != null) {
        query = query.limit(limitDays);
      }

      final response = await query;

      if (response == null) return [];

      return (response as List).map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      print('❌ Fehler beim Abrufen des Gewichtsverlaufs: $e');
      return [];
    }
  }
}

