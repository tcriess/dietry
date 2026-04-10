import 'package:dietry/services/app_logger.dart';
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

      // Tag doesn't exist, create it
      final response = await _db.client.from('tags').insert({
        'name': name,
        'slug': slug,
        'created_by': _userId,
      }).select().single();

      final tag = Tag.fromJson(response);
      appLogger.i('✅ Tag erstellt: ${tag.name}');
      return tag;
    } catch (e) {
      appLogger.e('❌ Fehler beim Abrufen/Erstellen von Tag: $e');
      return null;
    }
  }

  /// Setze öffentliche Tags für ein Lebensmittel (nur für Eigentümer)
  ///
  /// Löscht alle existierenden öffentlichen Tags und setzt neue.
  Future<bool> setFoodPublicTags(String foodId, List<Tag> tags) async {
    try {
      appLogger.d('🏷️ Setze öffentliche Tags für Food $foodId (${tags.length} Tags)');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return false;
      }

      // Delete all existing public tags for this food
      await _db.client.from('food_public_tags').delete().eq('food_id', foodId);

      // Insert new tags
      if (tags.isNotEmpty) {
        final insertData = tags.map((tag) => {
          'food_id': foodId,
          'tag_id': tag.id,
        }).toList();

        await _db.client.from('food_public_tags').insert(insertData);
      }

      appLogger.i('✅ Öffentliche Tags aktualisiert');
      return true;
    } catch (e) {
      appLogger.e('❌ Fehler beim Setzen öffentlicher Tags: $e');
      return false;
    }
  }

  /// Setze private Tags für ein Lebensmittel (für den aktuellen User)
  ///
  /// Löscht alle existierenden privaten Tags des Users für dieses Lebensmittel
  /// und setzt neue.
  Future<bool> setUserFoodTags(String foodId, List<Tag> tags) async {
    try {
      appLogger.d('🏷️ Setze private Tags für Food $foodId (${tags.length} Tags)');

      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) {
        appLogger.w('⚠️ Token ungültig');
        return false;
      }

      // Delete all existing user tags for this food
      await _db.client
        .from('user_food_tags')
        .delete()
        .eq('food_id', foodId)
        .eq('user_id', _userId!);

      // Insert new tags
      if (tags.isNotEmpty) {
        final insertData = tags.map((tag) => {
          'user_id': _userId,
          'food_id': foodId,
          'tag_id': tag.id,
        }).toList();

        await _db.client.from('user_food_tags').insert(insertData);
      }

      appLogger.i('✅ Private Tags aktualisiert');
      return true;
    } catch (e) {
      appLogger.e('❌ Fehler beim Setzen privater Tags: $e');
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
}
