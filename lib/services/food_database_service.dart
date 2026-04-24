import 'package:dietry/services/app_logger.dart';
import '../models/food_item.dart';
import 'neon_database_service.dart';
import 'package:dio/dio.dart';

/// Service für Verwaltung der Food-Datenbank (food_database Tabelle)
/// 
/// Ermöglicht:
/// - Suche nach Lebensmitteln (public + eigene)
/// - CRUD für eigene private Lebensmittel
/// - Barcode-Suche (zukünftig)
class FoodDatabaseService {
  final NeonDatabaseService _db;
  
  FoodDatabaseService(this._db);
  
  String? get _userId => _db.userId;
  
  /// Suche Lebensmittel nach Name und Brand
  ///
  /// Findet alle public + eigenen private foods die [query] im Namen oder Brand enthalten.
  /// Case-insensitive Suche mit Trigram-Ähnlichkeits-Ranking.
  /// Optional filter by tags (all requested tags must be present).
  /// Ergebnisse sortiert nach: Eigene zuerst, dann beste Ähnlichkeit, dann zuletzt verwendet, dann alphabetisch.
  Future<List<FoodItem>> searchFoods(String query, {
    int limit = 50,
    List<String> filterTags = const [],  // tag slugs to filter by
  }) async {
    try {
      appLogger.d('🔍 Suche nach Lebensmitteln: "$query" (Limit: $limit${filterTags.isNotEmpty ? ', Tags: ${filterTags.join(", ")}' : ''})');

      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return [];
      }

      // Rufe RPC-Funktion auf
      final response = await _db.client.rpc(
        'search_food_database',
        params: {
          'query': query,
          'filter_tags': filterTags.isEmpty ? null : filterTags,
          'max_results': limit,
        },
      );

      final foods = (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();

      appLogger.i('✅ ${foods.length} Lebensmittel gefunden');
      return foods;
    } catch (e) {
      appLogger.e('❌ Fehler bei Food-Suche: $e');
      return [];
    }
  }
  
  /// Hole Lebensmittel per ID
  Future<FoodItem?> getFoodById(String id) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;
      
      final response = await _db.client
        .from('food_database')
        .select()
        .eq('id', id)
        .maybeSingle();
      
      if (response == null) return null;
      
      return FoodItem.fromJson(response);
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden des Foods: $e');
      return null;
    }
  }

  /// Hole alle eigenen private Foods (mit Tags)
  /// Own foods only — for the manage screen (FoodDatabaseScreen).
  /// Uses list_own_foods(): no similarity(), index scan on user_id.
  Future<List<FoodItem>> getMyFoods() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final response = await _db.client.rpc(
        'list_own_foods',
        params: {'max_results': 500},
      );

      return (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden eigener Foods: $e');
      return [];
    }
  }

  /// Own foods + public approved foods — for the add-food screen (AddFoodEntryScreen).
  /// Uses list_visible_foods(): no similarity(), own foods shown first.
  Future<List<FoodItem>> getVisibleFoods() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final response = await _db.client.rpc(
        'list_visible_foods',
        params: {'max_results': 300},
      );

      return (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden sichtbarer Foods: $e');
      return [];
    }
  }

  /// Hole Foods nach Kategorie
  Future<List<FoodItem>> getFoodsByCategory(String category) async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('food_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .eq('category', category)
        .order('name');
      
      return (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden von Foods nach Kategorie: $e');
      return [];
    }
  }

  /// Erstelle eigenes private Food
  /// 
  /// User kann KEINE public foods erstellen (RLS blockiert das).
  Future<FoodItem> createFood(FoodItem food) async {
    try {
      appLogger.i('💾 Erstelle neues Food: ${food.name}');

      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      final json = food.toJson();
      json['user_id'] = userId;
      json.remove('id');  // ID wird von DB generiert

      appLogger.d('   📤 Sende INSERT via Dio...');

      // Verwende Dio statt Postgrest Client (Prefer-Header Problem)
      final response = await _db.dioClient.post(
        '/food_database',
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

      final created = FoodItem.fromJson((response.data as List).first as Map<String, dynamic>);
      appLogger.i('✅ Food erstellt: ${created.id}');
      return created;
    } catch (e) {
      appLogger.e('❌ Fehler beim Erstellen des Foods: $e');
      rethrow;
    }
  }
  
  /// Aktualisiere eigenes Food
  ///
  /// Nur eigene private foods können aktualisiert werden.
  Future<FoodItem> updateFood(FoodItem food) async {
    try {
      appLogger.i('💾 Aktualisiere Food: ${food.id}');

      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      final json = food.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();

      appLogger.d('   📤 Sende UPDATE via Dio...');

      // Verwende Dio statt Postgrest Client (Prefer-Header Problem)
      final response = await _db.dioClient.patch(
        '/food_database?id=eq.${food.id}&user_id=eq.$userId',
        data: json,
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );

      if (response.statusCode != 200 || response.data == null || (response.data as List).isEmpty) {
        throw Exception('UPDATE fehlgeschlagen: ${response.statusCode}');
      }

      final updated = FoodItem.fromJson((response.data as List).first as Map<String, dynamic>);
      appLogger.i('✅ Food aktualisiert: ${updated.id}');
      return updated;
    } catch (e) {
      appLogger.e('❌ Fehler beim Aktualisieren des Foods: $e');
      rethrow;
    }
  }
  
  /// Lösche eigenes Food
  ///
  /// Nur eigene private foods können gelöscht werden.
  /// ACHTUNG: Löscht auch food_id Referenzen in food_entries (ON DELETE SET NULL)!
  Future<void> deleteFood(String id) async {
    try {
      appLogger.i('🗑️  Lösche Food: $id');

      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        throw Exception('Token ungültig');
      }

      final userId = _userId;
      if (userId == null) {
        throw Exception('Keine User-ID verfügbar');
      }

      appLogger.d('   📤 Sende DELETE via Dio...');

      // Verwende Dio statt Postgrest Client (Prefer-Header Problem)
      final response = await _db.dioClient.delete(
        '/food_database?id=eq.$id&user_id=eq.$userId',
        options: Options(
          headers: {
            'Prefer': 'return=minimal',
          },
        ),
      );

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('DELETE fehlgeschlagen: ${response.statusCode}');
      }

      appLogger.i('✅ Food gelöscht');
    } catch (e) {
      appLogger.e('❌ Fehler beim Löschen des Foods: $e');
      rethrow;
    }
  }
  
  /// Suche Food per Barcode (zukünftig für Scanner-Funktion)
  Future<FoodItem?> searchByBarcode(String barcode) async {
    try {
      appLogger.d('🔍 Suche per Barcode: $barcode');

      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return null;

      final userId = _userId;
      if (userId == null) return null;

      final response = await _db.client
        .from('food_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .eq('barcode', barcode)
        .maybeSingle();

      if (response == null) {
        appLogger.i('ℹ️ Kein Food mit Barcode $barcode gefunden');
        return null;
      }

      final food = FoodItem.fromJson(response);
      appLogger.i('✅ Food gefunden: ${food.name}');
      return food;
    } catch (e) {
      appLogger.e('❌ Fehler bei Barcode-Suche: $e');
      return null;
    }
  }
  
  /// Gibt alle als Favorit markierten eigenen Lebensmittel zurück.
  Future<List<FoodItem>> getFavouriteFoods() async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      final userId = _userId;
      if (userId == null) return [];
      final response = await _db.client
          .from('food_database')
          .select()
          .eq('user_id', userId)
          .eq('is_favourite', true)
          .order('name');
      return (response as List)
          .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Favoriten: $e');
      return [];
    }
  }

  /// Setzt oder entfernt das Favoriten-Flag für ein eigenes Lebensmittel.
  Future<void> toggleFoodFavourite(String id, {required bool isFavourite}) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) throw Exception('Token ungültig');
      final userId = _userId;
      if (userId == null) throw Exception('Keine User-ID');
      await _db.dioClient.patch(
        '/food_database?id=eq.$id&user_id=eq.$userId',
        data: {
          'is_favourite': isFavourite,
          'updated_at': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );
    } catch (e) {
      appLogger.e('❌ Fehler beim Setzen des Favoriten: $e');
      rethrow;
    }
  }

  /// Hole alle verfügbaren Kategorien
  /// Returns food IDs ordered by when they were most recently logged,
  /// deduped (first occurrence = most recent). Used for MRU sort.
  Future<List<String>> getRecentlyUsedFoodIds({int limit = 300}) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];

      final response = await _db.client
        .from('food_entries')
        .select('food_id')
        .not('food_id', 'is', null)
        .order('entry_date', ascending: false)
        .limit(limit);

      final seen = <String>{};
      final result = <String>[];
      for (final row in (response as List)) {
        final id = row['food_id'] as String?;
        if (id != null && seen.add(id)) result.add(id);
      }
      return result;
    } catch (e) {
      appLogger.w('⚠️ Fehler beim Laden der zuletzt verwendeten Foods: $e');
      return [];
    }
  }

  Future<List<String>> getCategories() async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('food_database')
        .select('category')
        .or('is_public.eq.true,user_id.eq.$userId')
        .not('category', 'is', null);
      
      final categories = (response as List)
        .map((row) => row['category'] as String?)
        .whereType<String>()  // Filter out nulls
        .toSet()  // Deduplizieren
        .toList()
        ..sort();
      
      return categories;
    } catch (e) {
      appLogger.e('❌ Fehler beim Laden der Kategorien: $e');
      return [];
    }
  }
}

