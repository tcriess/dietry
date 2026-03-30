// Food Entry Service für CRUD-Operationen
import '../models/models.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';

class FoodEntryService {
  final NeonDatabaseService _db;
  
  FoodEntryService(this._db);
  
  /// Hole alle Food Entries für ein bestimmtes Datum
  Future<List<FoodEntry>> getFoodEntriesForDate(DateTime date) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        print('⚠️ Token ungültig');
        return [];
      }
      
      final userId = _db.userId;
      if (userId == null) {
        print('⚠️ Keine User-ID verfügbar');
        return [];
      }
      
      final dateStr = date.toIso8601String().split('T')[0];
      
      print('   Query: user_id=$userId, entry_date=$dateStr');
      
      final response = await _db.client
        .from('food_entries')
        .select()
        .eq('user_id', userId)  // ✅ User-Filter hinzugefügt
        .eq('entry_date', dateStr)  // ✅ Korrigiert: entry_date statt date
        .order('created_at', ascending: false);
      
      return (response as List)
        .map((json) => FoodEntry.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Abrufen der Food Entries: $e');
      rethrow;
    }
  }
  
  /// Holt leichte Stubs (id + updated_at) für Delta-Sync-Vergleich.
  /// Deutlich weniger Daten als ein voller Fetch.
  Future<List<({String id, DateTime updatedAt})>> getFoodEntryStubs(
      DateTime date) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _db.userId;
      if (userId == null) return [];

      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _db.client
          .from('food_entries')
          .select('id,updated_at')
          .eq('user_id', userId)
          .eq('entry_date', dateStr);

      return (response as List).map((r) {
        final m = r as Map<String, dynamic>;
        return (
          id: m['id'] as String,
          updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
        );
      }).toList();
    } catch (e) {
      print('❌ FoodEntryService.getFoodEntryStubs: $e');
      return [];
    }
  }

  /// Holt vollständige Records für eine Liste von IDs (für Delta-Sync).
  Future<List<FoodEntry>> getFoodEntriesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final response = await _db.client
          .from('food_entries')
          .select()
          .inFilter('id', ids);

      return (response as List)
          .map((json) => FoodEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ FoodEntryService.getFoodEntriesByIds: $e');
      return [];
    }
  }

  /// Erstelle einen neuen Food Entry
  Future<FoodEntry> createFoodEntry(FoodEntry entry) async {
    try {
      print('💾 Erstelle Food-Entry: ${entry.name}');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _db.userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      final json = entry.toJson();
      json['user_id'] = userId;
      // Entferne id für INSERT (wird von DB generiert)
      json.remove('id');
      
      print('   Führe INSERT via Dio aus (umgeht postgrest Prefer-Header-Bug)...');
      
      // ✅ Verwende Dio direkt (wie insertUser) um postgrest Bug zu umgehen
      final response = await _db.dioClient.post(
        '/food_entries',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',  // Wir wollen das erstellte Objekt zurück
          },
        ),
      );
      
      if (response.statusCode != 201) {
        throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
      }
      
      // Response ist Array mit einem Element (bei return=representation)
      final createdJson = (response.data as List).first as Map<String, dynamic>;
      final created = FoodEntry.fromJson(createdJson);
      
      print('✅ Food-Entry erfolgreich erstellt: ${created.id}');
      return created;
    } catch (e) {
      print('❌ Fehler beim Erstellen des Food Entry: $e');
      rethrow;
    }
  }
  
  /// Aktualisiere einen Food Entry
  Future<FoodEntry> updateFoodEntry(FoodEntry entry) async {
    try {
      print('💾 Aktualisiere Food-Entry: ${entry.id}');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _db.userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      final json = entry.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();
      
      print('   Führe UPDATE via Dio aus...');
      
      // ✅ UPDATE via Dio (umgeht postgrest Prefer-Header-Bug)
      final response = await _db.dioClient.patch(
        '/food_entries?id=eq.${entry.id}&user_id=eq.$userId',
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
      
      // Response ist Array mit einem Element
      final updatedJson = (response.data as List).first as Map<String, dynamic>;
      final updated = FoodEntry.fromJson(updatedJson);
      
      print('✅ Food-Entry erfolgreich aktualisiert');
      return updated;
    } catch (e) {
      print('❌ Fehler beim Aktualisieren des Food Entry: $e');
      rethrow;
    }
  }
  
  /// Lösche einen Food Entry
  Future<void> deleteFoodEntry(String id) async {
    try {
      print('🗑️  Lösche Food-Entry: $id');
      
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }
      
      final userId = _db.userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }
      
      print('   Führe DELETE via Dio aus...');
      
      // ✅ DELETE via Dio (umgeht postgrest Prefer-Header-Bug)
      final response = await _db.dioClient.delete(
        '/food_entries?id=eq.$id&user_id=eq.$userId',
        options: Options(
          headers: {
            'Prefer': 'return=minimal',  // Wir brauchen keine Response
          },
        ),
      );
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
      }
      
      print('✅ Food-Entry erfolgreich gelöscht');
    } catch (e) {
      print('❌ Fehler beim Löschen des Food Entry: $e');
      rethrow;
    }
  }
  
  /// Hole alle Food Entries für einen Datumsbereich
  Future<List<FoodEntry>> getFoodEntriesForRange(DateTime start, DateTime end) async {
    try {
      final startStr = start.toIso8601String().split('T')[0];
      final endStr = end.toIso8601String().split('T')[0];
      
      final response = await _db.client
        .from('food_entries')
        .select()
        .gte('date', startStr)
        .lte('date', endStr)
        .order('date', ascending: false)
        .order('created_at', ascending: false);
      
      return (response as List)
        .map((json) => FoodEntry.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Abrufen der Food Entries (Range): $e');
      rethrow;
    }
  }
}

