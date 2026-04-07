import 'package:dietry/services/app_logger.dart';
import '../models/physical_activity.dart';
import '../models/user_body_data.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';

/// Service für physische Aktivitäten (Tracking & Health Connect Integration)
class PhysicalActivityService {
  final NeonDatabaseService _db;

  PhysicalActivityService(this._db);

  String? get _userId => _db.userId;

  /// Hole alle Aktivitäten für einen bestimmten Tag
  Future<List<PhysicalActivity>> getActivitiesForDate(DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig - kann Aktivitäten nicht laden');
        return [];
      }

      final userId = _userId;
      if (userId == null) {
        appLogger.w('⚠️ Keine User-ID verfügbar');
        return [];
      }

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final response = await _db.client
          .from('physical_activities')
          .select()
          .eq('user_id', userId)
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String())
          .order('start_time', ascending: false);

      return (response as List)
          .map((item) => PhysicalActivity.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Aktivitäten: $e');
      return [];
    }
  }

  /// Holt leichte Stubs (id + updated_at) für Delta-Sync-Vergleich.
  Future<List<({String id, DateTime updatedAt})>> getActivityStubs(
      DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _userId;
      if (userId == null) return [];

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final response = await _db.client
          .from('physical_activities')
          .select('id,updated_at')
          .eq('user_id', userId)
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());

      return (response as List).map((r) {
        final m = r as Map<String, dynamic>;
        return (
          id: m['id'] as String,
          updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
        );
      }).toList();
    } catch (e) {
      appLogger.e('❌ PhysicalActivityService.getActivityStubs: $e');
      return [];
    }
  }

  /// Holt vollständige Records für eine Liste von IDs (für Delta-Sync).
  Future<List<PhysicalActivity>> getActivitiesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final response = await _db.client
          .from('physical_activities')
          .select()
          .inFilter('id', ids);

      return (response as List)
          .map((item) => PhysicalActivity.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ PhysicalActivityService.getActivitiesByIds: $e');
      return [];
    }
  }

  /// Hole Aktivitäten für einen Zeitraum
  Future<List<PhysicalActivity>> getActivitiesInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return [];
      }

      final userId = _userId;
      if (userId == null) return [];

      final response = await _db.client
          .from('physical_activities')
          .select()
          .eq('user_id', userId)
          .gte('start_time', start.toIso8601String())
          .lte('start_time', end.toIso8601String())
          .order('start_time', ascending: false);

      return (response as List)
          .map((item) => PhysicalActivity.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Aktivitäten: $e');
      return [];
    }
  }

  /// Speichere eine Aktivität (CREATE)
  Future<PhysicalActivity> saveActivity(PhysicalActivity activity) async {
    try {
      appLogger.i('💾 Erstelle Aktivität: ${activity.activityType.displayName}');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig - kann Aktivität nicht speichern');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      final json = activity.toJson();
      json['user_id'] = userId;
      json.remove('id');  // ID wird von DB generiert

      appLogger.d('   Führe INSERT via Dio aus...');

      // ✅ INSERT via Dio (umgeht postgrest Prefer-Header-Bug)
      final response = await _db.dioClient.post(
        '/physical_activities',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );

      if (response.statusCode != 201) {
        throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
      }

      final createdJson = (response.data as List).first as Map<String, dynamic>;
      final created = PhysicalActivity.fromJson(createdJson);

      appLogger.i('✅ Aktivität erfolgreich erstellt: ${created.id}');
      return created;
    } catch (e) {
      appLogger.e('❌ Fehler beim Speichern der Aktivität: $e');
      rethrow;
    }
  }

  /// Aktualisiere eine Aktivität
  Future<PhysicalActivity> updateActivity(PhysicalActivity activity) async {
    try {
      appLogger.i('💾 Aktualisiere Aktivität: ${activity.id}');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      final json = activity.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();

      appLogger.d('   Führe UPDATE via Dio aus...');

      // ✅ UPDATE via Dio
      final response = await _db.dioClient.patch(
        '/physical_activities?id=eq.${activity.id}&user_id=eq.$userId',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('UPDATE fehlgeschlagen: ${response.statusCode}');
      }

      final updatedJson = (response.data as List).first as Map<String, dynamic>;
      final updated = PhysicalActivity.fromJson(updatedJson);

      appLogger.i('✅ Aktivität erfolgreich aktualisiert');
      return updated;
    } catch (e) {
      appLogger.e('❌ Fehler beim Aktualisieren der Aktivität: $e');
      rethrow;
    }
  }

  /// Lösche eine Aktivität
  Future<void> deleteActivity(String id) async {
    try {
      appLogger.i('🗑️  Lösche Aktivität: $id');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      appLogger.d('   Führe DELETE via Dio aus...');

      // ✅ DELETE via Dio
      final response = await _db.dioClient.delete(
        '/physical_activities?id=eq.$id&user_id=eq.$userId',
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
      }

      appLogger.i('✅ Aktivität erfolgreich gelöscht');
    } catch (e) {
      appLogger.e('❌ Fehler beim Löschen der Aktivität: $e');
      rethrow;
    }
  }

  /// Hole tägliche Zusammenfassung (View)
  Future<Map<String, dynamic>?> getDailySummary(DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;

      final userId = _userId;
      if (userId == null) return null;

      final dateStr = date.toIso8601String().split('T')[0];

      final response = await _db.client
          .from('daily_activity_summary')
          .select()
          .eq('user_id', userId)
          .eq('activity_date', dateStr)
          .single();

      return response as Map<String, dynamic>?;
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Tages-Zusammenfassung: $e');
      return null;
    }
  }

  /// Hole wöchliche Zusammenfassung (View)
  Future<List<Map<String, dynamic>>> getWeeklySummary({int weeks = 4}) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final userId = _userId;
      if (userId == null) return [];

      final response = await _db.client
          .from('weekly_activity_summary')
          .select()
          .eq('user_id', userId)
          .order('week_start', ascending: false)
          .limit(weeks);

      return (response as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Wochen-Zusammenfassung: $e');
      return [];
    }
  }

  /// Berechne effektives Aktivitätslevel basierend auf letzten 7 Tagen
  /// 
  /// Nutzt tatsächliche Aktivitäten um ActivityLevel zu schätzen
  /// Kann für automatische Goal-Anpassung verwendet werden
  Future<ActivityLevel?> calculateEffectiveActivityLevel() async {
    try {
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 7));

      final activities = await getActivitiesInRange(start: start, end: end);

      if (activities.isEmpty) {
        return null; // Keine Daten
      }

      // Berechne durchschnittliche Trainings-Minuten pro Tag
      final totalMinutes = activities.fold<int>(
        0,
        (sum, activity) => sum + activity.calculatedDuration,
      );
      final avgMinutesPerDay = totalMinutes / 7;

      // Berechne Anzahl aktiver Tage (mindestens 20 Min Aktivität)
      final activitiesPerDay = <DateTime, int>{};
      for (var activity in activities) {
        final date = DateTime(
          activity.startTime.year,
          activity.startTime.month,
          activity.startTime.day,
        );
        activitiesPerDay[date] = (activitiesPerDay[date] ?? 0) + activity.calculatedDuration;
      }
      final activeDays = activitiesPerDay.values.where((mins) => mins >= 20).length;

      // Schätze ActivityLevel
      if (avgMinutesPerDay < 15) {
        return ActivityLevel.sedentary;
      } else if (activeDays <= 3) {
        return ActivityLevel.light;
      } else if (activeDays <= 5) {
        return ActivityLevel.moderate;
      } else if (avgMinutesPerDay >= 90) {
        return ActivityLevel.veryActive;
      } else {
        return ActivityLevel.active;
      }
    } catch (e) {
      appLogger.e('❌ Fehler bei Aktivitätslevel-Berechnung: $e');
      return null;
    }
  }

  /// Synchronisiere Aktivitäten von Health Connect
  /// 
  /// Wird später implementiert wenn Health Connect Plugin integriert ist
  /// Placeholder für zukünftige Integration
  Future<int> syncFromHealthConnect({
    required DateTime start,
    required DateTime end,
  }) async {
    // TODO: Health Connect Integration
    // 1. Health Connect Plugin initialisieren
    // 2. Berechtigungen prüfen/anfordern
    // 3. Aktivitäten abrufen (Exercise Sessions)
    // 4. In PhysicalActivity konvertieren
    // 5. Mit health_connect_record_id speichern (verhindert Duplikate)

    appLogger.i('ℹ️ Health Connect Sync noch nicht implementiert');
    appLogger.i('   Vorbereitet für: health_connect_record_id UNIQUE Constraint');
    return 0;
  }

  /// Prüfe ob eine Health Connect Aktivität bereits synchronisiert wurde
  Future<bool> isHealthConnectActivitySynced(String healthConnectRecordId) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return false;

      final userId = _userId;
      if (userId == null) return false;

      final response = await _db.client
          .from('physical_activities')
          .select('id')
          .eq('user_id', userId)
          .eq('health_connect_record_id', healthConnectRecordId)
          .limit(1);

      return (response as List).isNotEmpty;
    } catch (e) {
      appLogger.e('❌ Fehler beim Prüfen: $e');
      return false;
    }
  }
}

