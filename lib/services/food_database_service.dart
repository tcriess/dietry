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
  
  /// Suche Lebensmittel nach Name
  /// 
  /// Findet alle public + eigenen private foods die [query] im Namen enthalten.
  /// Case-insensitive Suche.
  Future<List<FoodItem>> searchFoods(String query, {int limit = 50}) async {
    try {
      print('🔍 Suche nach Lebensmitteln: "$query"');
      
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
        .from('food_database')
        .select()
        .or('is_public.eq.true,user_id.eq.$userId')
        .ilike('name', '%${query.toLowerCase()}%')
        .order('is_public', ascending: false)  // Eigene zuerst
        .order('name')
        .limit(limit);
      
      final foods = (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
      
      print('✅ ${foods.length} Lebensmittel gefunden');
      return foods;
    } catch (e) {
      print('❌ Fehler bei Food-Suche: $e');
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
      
      return FoodItem.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Fehler beim Laden des Foods: $e');
      return null;
    }
  }
  
  /// Hole alle eigenen private Foods
  Future<List<FoodItem>> getMyFoods() async {
    try {
      // Token prüfen
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return [];
      
      final userId = _userId;
      if (userId == null) return [];
      
      final response = await _db.client
        .from('food_database')
        .select()
        .eq('user_id', userId)
        .order('is_public', ascending: false)  // Öffentliche zuerst
        .order('created_at', ascending: false);
      
      return (response as List)
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
    } catch (e) {
      print('❌ Fehler beim Laden eigener Foods: $e');
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
      print('❌ Fehler beim Laden von Foods nach Kategorie: $e');
      return [];
    }
  }
  
  /// Erstelle eigenes private Food
  /// 
  /// User kann KEINE public foods erstellen (RLS blockiert das).
  Future<FoodItem> createFood(FoodItem food) async {
    try {
      print('💾 Erstelle neues Food: ${food.name}');
      
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
      
      print('   📤 Sende INSERT via Dio...');
      
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
      print('✅ Food erstellt: ${created.id}');
      return created;
    } catch (e) {
      print('❌ Fehler beim Erstellen des Foods: $e');
      rethrow;
    }
  }
  
  /// Aktualisiere eigenes Food
  /// 
  /// Nur eigene private foods können aktualisiert werden.
  Future<FoodItem> updateFood(FoodItem food) async {
    try {
      print('💾 Aktualisiere Food: ${food.id}');
      
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
      
      print('   📤 Sende UPDATE via Dio...');
      
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
      print('✅ Food aktualisiert: ${updated.id}');
      return updated;
    } catch (e) {
      print('❌ Fehler beim Aktualisieren des Foods: $e');
      rethrow;
    }
  }
  
  /// Lösche eigenes Food
  /// 
  /// Nur eigene private foods können gelöscht werden.
  /// ACHTUNG: Löscht auch food_id Referenzen in food_entries (ON DELETE SET NULL)!
  Future<void> deleteFood(String id) async {
    try {
      print('🗑️  Lösche Food: $id');
      
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
      
      print('✅ Food gelöscht');
    } catch (e) {
      print('❌ Fehler beim Löschen des Foods: $e');
      rethrow;
    }
  }
  
  /// Suche Food per Barcode (zukünftig für Scanner-Funktion)
  Future<FoodItem?> searchByBarcode(String barcode) async {
    try {
      print('🔍 Suche per Barcode: $barcode');
      
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
        print('ℹ️ Kein Food mit Barcode $barcode gefunden');
        return null;
      }
      
      final food = FoodItem.fromJson(response as Map<String, dynamic>);
      print('✅ Food gefunden: ${food.name}');
      return food;
    } catch (e) {
      print('❌ Fehler bei Barcode-Suche: $e');
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
      print('❌ Fehler beim Laden der Favoriten: $e');
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
      print('❌ Fehler beim Setzen des Favoriten: $e');
      rethrow;
    }
  }

  /// Hole alle verfügbaren Kategorien
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
        .map((row) => row['category'] as String)
        .toSet()  // Deduplizieren
        .toList()
        ..sort();
      
      return categories;
    } catch (e) {
      print('❌ Fehler beim Laden der Kategorien: $e');
      return [];
    }
  }
}

