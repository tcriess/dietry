import 'package:dietry/services/app_logger.dart';
import 'package:dio/dio.dart';
import '../models/tag.dart';
import 'neon_database_service.dart';

/// Service für Verwaltung von Food- und Meal-Template-Tags
///
/// Ermöglicht:
/// - Tag-Suche und -Erstellung
/// - Verwaltung von öffentlichen und privaten Food-Tags
/// - Abruf verfügbarer Tags zum Filtern
class TagService {
  final NeonDatabaseService _db;

  TagService(this._db);

  String? get _userId => _db.userId;

  /// Suche Tag-Vorschläge nach Name (case-insensitive)
  Future<List<Tag>> fetchTagSuggestions(String query) async {
    try {
      if (query.isEmpty) return [];

      appLogger.d('🔍 Suche Tag-Vorschläge für: "$query"');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return [];
      }

      // Query tags by name similarity
      final response = await _db.client.from('tags').select().ilike('name', '%$query%').limit(10);

      final tags = (response as List)
        .map((json) => Tag.fromJson(json as Map<String, dynamic>))
        .toList();

      appLogger.d('✅ ${tags.length} Tag-Vorschläge gefunden');
      return tags;
    } catch (e) {
      appLogger.e('❌ Fehler beim Abrufen von Tag-Vorschlägen: $e');
      return [];
    }
  }

  /// Hole oder erstelle einen Tag basierend auf dem Namen
  ///
  /// Versucht zuerst, einen Tag mit dem berechneten Slug zu finden.
  /// Falls nicht vorhanden, wird er erstellt.
  Future<Tag?> getOrCreateTag(String name) async {
    try {
      if (name.isEmpty) {
        appLogger.w('⚠️ Tag-Name ist leer');
        return null;
      }

      final slug = Tag.toSlug(name);
      appLogger.d('🏷️ Hole oder erstelle Tag: "$name" (slug: "$slug")');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return null;
      }

      // Try to find existing tag
      final existing = await _db.client.from('tags').select().eq('slug', slug).limit(1);

      if (existing.isNotEmpty) {
        final tag = Tag.fromJson(existing.first);
        appLogger.d('✅ Tag gefunden: ${tag.name}');
        return tag;
      }

      // Tag doesn't exist, create it using dioClient (like FoodDatabaseService)
      final response = await _db.dioClient.post(
        '/tags',
        data: {
          'name': name,
          'slug': slug,
          'created_by': _userId,
        },
        options: Options(
          headers: {
            'Prefer': 'return=representation',
          },
        ),
      );

      if (response.statusCode != 201 || response.data == null || (response.data as List).isEmpty) {
        throw Exception('INSERT fehlgeschlagen: ${response.statusCode}');
      }

      final tag = Tag.fromJson((response.data as List).first);
      appLogger.i('✅ Tag erstellt: ${tag.name}');
      return tag;
    } catch (e) {
      appLogger.e('❌ Fehler beim Abrufen/Erstellen von Tag: $e');
      return null;
    }
  }

  /// Setze Tags für ein Lebensmittel (für den aktuellen User)
  ///
  /// Löscht alle existierenden Tags des Users für dieses Lebensmittel und setzt neue.
  /// Wenn der User der Food-Besitzer ist, werden diese Tags für alle sichtbar.
  /// Andernfalls sichtbar nur für diesen User.
  Future<bool> setFoodTags(String foodId, List<Tag> tags) async {
    try {
      appLogger.d('🏷️ Setze Tags für Food $foodId (${tags.length} Tags)');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return false;
      }

      // Delete all existing user tags for this food using dioClient
      await _db.dioClient.delete(
        '/user_food_tags?food_id=eq.$foodId&user_id=eq.$_userId',
        options: Options(headers: {'Prefer': 'return=minimal'}),
      );

      // Insert new tags using dioClient
      if (tags.isNotEmpty) {
        final insertData = tags.map((tag) => {
          'user_id': _userId,
          'food_id': foodId,
          'tag_id': tag.id,
        }).toList();

        await _db.dioClient.post(
          '/user_food_tags',
          data: insertData,
          options: Options(headers: {'Prefer': 'return=minimal'}),
        );
      }

      appLogger.i('✅ Tags aktualisiert');
      return true;
    } catch (e) {
      appLogger.e('❌ Fehler beim Setzen von Tags: $e');
      return false;
    }
  }

  /// Hole alle verfügbaren Tags zum Filtern
  ///
  /// Ruft die RPC-Funktion `get_available_food_tags()` auf,
  /// die alle Tags in den sichtbaren Lebensmitteln des Users zurückgibt.
  Future<List<Tag>> getAvailableFoodTags() async {
    try {
      appLogger.d('🏷️ Hole verfügbare Tags zum Filtern');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return [];
      }

      final response = await _db.client.rpc('get_available_food_tags');

      final tags = (response as List)
        .map((json) => Tag.fromJson(json as Map<String, dynamic>))
        .toList();

      appLogger.i('✅ ${tags.length} verfügbare Tags gefunden');
      return tags;
    } catch (e) {
      appLogger.e('❌ Fehler beim Abrufen verfügbarer Tags: $e');
      return [];
    }
  }

  /// Hole Tags für ein spezifisches Lebensmittel (die der aktuelle User sehen kann)
  ///
  /// Ruft user_food_tags ab wo food_id = foodId
  /// Sichtbar: Tags vom Owner (Food-Besitzer) ODER vom aktuellen User
  Future<List<Tag>> getFoodTags(String foodId) async {
    try {
      appLogger.d('🏷️ Hole Tags für Food $foodId');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return [];
      }

      // Query user_food_tags for this food
      // RLS will automatically filter to visible tags (owner + current user)
      final response = await _db.client
          .from('user_food_tags')
          .select('tag_id, tags(id, name, slug)')
          .eq('food_id', foodId);

      final tags = <Tag>[];
      for (final row in response as List) {
        final tagData = row['tags'];
        if (tagData is Map<String, dynamic>) {
          tags.add(Tag.fromJson(tagData));
        }
      }

      appLogger.d('✅ ${tags.length} Tags für Food gefunden');
      return tags;
    } catch (e) {
      appLogger.e('❌ Fehler beim Abrufen von Tags für Food: $e');
      return [];
    }
  }
}
