import '../models/activity_item.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';

/// Service für Verwaltung der Activity-Datenbank (activity_database Tabelle)
/// 
/// Ermöglicht:
/// - Suche nach Aktivitäten (public + eigene)
/// - CRUD für eigene private Aktivitäten
/// - MET-basierte Kalorien-Berechnung
class ActivityDatabaseService {
  final NeonDatabaseService _db;
  
  ActivityDatabaseService(this._db);
  
  String? get _userId => _db.userId;
  
  /// Suche Aktivitäten nach Name
  /// 
  /// Findet alle public + eigenen private activities die [query] im Namen enthalten.
  /// Case-insensitive Suche.
  Future<List<ActivityItem>> searchActivities(String query, {int limit = 50}) async {
    try {
      print('🔍 Suche nach Aktivitäten: "$query"');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig');
        return [];
      }
      
      final userId = _userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar');
        return [];
      }
      
      // Suche mit ILIKE (case-insensitive)
      final response = await _db.client
        .from('activity_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .ilike('name', '%${query.toLowerCase()}%')
        .order('is_public', ascending: false)  // Eigene zuerst
        .order('name')
        .limit(limit);
      
      final activities = (response as List)
        .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
        .toList();
      
      print('✅ ${activities.length} Aktivitäten gefunden');
      return activities;
    } catch (e) {
      print('❌ Fehler bei Activity-Suche: $e');
      return [];
    }
  }
  
  /// Hole Aktivität per ID
  Future<ActivityItem?> getActivityById(String id) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;
      
      final response = await _db.client
        .from('activity_database')
        .select()
        .eq('id', id)
        .maybeSingle();
      
      if (response == null) return null;
      
      return ActivityItem.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Fehler beim Laden der Aktivität: $e');
      return null;
    }
  }
  
  /// Hole alle eigenen private Activities
  Future<List<ActivityItem>> getMyActivities() async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('activity_database')
        .select()
        .eq('user_id', userId)
        .order('is_public', ascending: false)
        .order('created_at', ascending: false);
      
      return (response as List)
        .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Laden eigener Activities: $e');
      return [];
    }
  }
  
  /// Hole Activities nach Kategorie
  Future<List<ActivityItem>> getActivitiesByCategory(String category) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('activity_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .eq('category', category)
        .order('name');
      
      return (response as List)
        .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Laden von Activities nach Kategorie: $e');
      return [];
    }
  }
  
  /// Hole Activities nach Intensität
  Future<List<ActivityItem>> getActivitiesByIntensity(String intensity) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('activity_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .eq('intensity', intensity)
        .order('name');
      
      return (response as List)
        .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Laden von Activities nach Intensität: $e');
      return [];
    }
  }
  
  /// Hole alle public Activities (für Übersicht)
  Future<List<ActivityItem>> getPublicActivities() async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final response = await _db.client
        .from('activity_database')
        .select()
        .eq('is_public', true)
        .order('category')
        .order('name');
      
      return (response as List)
        .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Laden von public Activities: $e');
      return [];
    }
  }
  
  /// Erstelle eigene private Activity
  /// 
  /// User kann KEINE public activities erstellen (RLS blockiert das).
  Future<ActivityItem> createActivity(ActivityItem activity) async {
    try {
      print('💾 Erstelle neue Activity: ${activity.name}');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      // JSON vorbereiten
      final json = activity.toJson();
      json['user_id'] = userId;
      json['is_approved'] = false;  // Immer false bei Insert - nur Admin kann freigeben
      json.remove('id');  // ID wird von DB generiert
      
      print('   📤 Sende INSERT via Dio...');
      
      // Verwende Dio statt Postgrest Client (Schema-Cache + Prefer-Header Problem)
      final response = await _db.dioClient.post(
        '/activity_database',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );
      
      if (response.statusCode != 201 || response.data == null || (response.data as List).isEmpty) {
        throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
      }
      
      final created = ActivityItem.fromJson((response.data as List).first as Map<String, dynamic>);
      print('✅ Activity erstellt: ${created.id}');
      return created;
    } catch (e) {
      print('❌ Fehler beim Erstellen der Activity: $e');
      rethrow;
    }
  }
  
  /// Aktualisiere eigene Activity
  Future<ActivityItem> updateActivity(ActivityItem activity) async {
    try {
      print('📝 Aktualisiere Activity: ${activity.id}');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      // JSON vorbereiten
      final json = activity.toJson();
      json['user_id'] = userId;
      json['is_approved'] = false;  // Bearbeitung setzt Freigabe zurück
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');

      print('   📤 Sende PATCH via Dio...');

      // UPDATE via Dio (Schema-Cache + Prefer-Header Problem)
      final response = await _db.dioClient.patch(
        '/activity_database?id=eq.${activity.id}&user_id=eq.$userId',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );

      if (response.statusCode != 200 || response.data == null || (response.data as List).isEmpty) {
        throw Exception('PATCH fehlgeschlagen: ${response.statusCode}');
      }

      print('✅ Activity aktualisiert');
      return ActivityItem.fromJson((response.data as List).first as Map<String, dynamic>);
    } catch (e) {
      print('❌ Fehler beim Aktualisieren der Activity: $e');
      rethrow;
    }
  }
  
  /// Lösche eigene Activity
  Future<void> deleteActivity(String id) async {
    try {
      print('🗑️  Lösche Activity: $id');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      print('   📤 Sende DELETE via Dio...');
      
      // Verwende Dio statt Postgrest Client
      final response = await _db.dioClient.delete(
        '/activity_database?id=eq.$id&user_id=eq.$userId',
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
      }
      
      print('✅ Activity gelöscht');
    } catch (e) {
      print('❌ Fehler beim Löschen der Activity: $e');
      rethrow;
    }
  }
  
  /// Gibt alle als Favorit markierten eigenen Aktivitäten zurück.
  Future<List<ActivityItem>> getFavouriteActivities() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _userId;
      if (userId == null) return [];
      final response = await _db.client
          .from('activity_database')
          .select()
          .eq('user_id', userId)
          .eq('is_favourite', true)
          .order('name');
      return (response as List)
          .map((json) => ActivityItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Fehler beim Laden der Aktivitäts-Favoriten: $e');
      return [];
    }
  }

  /// Setzt oder entfernt das Favoriten-Flag für eine eigene Aktivität.
  Future<void> toggleActivityFavourite(String id, {required bool isFavourite}) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) throw Exception('Token ungültig');
      final userId = _userId;
      if (userId == null) throw Exception('Keine User-ID');
      await _db.dioClient.patch(
        '/activity_database?id=eq.$id&user_id=eq.$userId',
        data: {
          'is_favourite': isFavourite,
          'updated_at': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );
    } catch (e) {
      print('❌ Fehler beim Setzen des Aktivitäts-Favoriten: $e');
      rethrow;
    }
  }

  /// Berechne Kalorien für Activity
  ///
  /// Helper-Methode die ActivityItem.calculateCalories verwendet
  double calculateCalories({
    required ActivityItem activity,
    required double weightKg,
    required int durationMinutes,
  }) {
    return activity.calculateCalories(
      weightKg: weightKg,
      durationMinutes: durationMinutes,
    );
  }
}

