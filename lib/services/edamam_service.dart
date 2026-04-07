import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../models/food_item.dart';
import 'app_logger.dart';

/// Nährwertsuche via Edamam Food Database API.
///
/// Docs: https://developer.edamam.com/food-database-api-docs
/// Credentials via --dart-define-from-file (EDAMAM_APP_ID / EDAMAM_APP_KEY).
/// Nur in nativen Builds verfügbar — [AppConfig.hasEdamam] prüft ob Keys gesetzt.
class EdamamService {
  static const String _baseUrl =
      'https://api.edamam.com/api/food-database/v2/parser';

  Future<List<FoodItem>> searchByName(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    if (!AppConfig.hasEdamam) {
      appLogger.w('⚠️ Edamam: Keine API-Credentials (EDAMAM_APP_ID/EDAMAM_APP_KEY)');
      return [];
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'app_id': AppConfig.edamamAppId,
        'app_key': AppConfig.edamamAppKey,
        'ingr': query,
        'nutrition-type': 'logging',
      });

      appLogger.d('🌐 Edamam Request: GET ${uri.replace(queryParameters: {
        ...uri.queryParameters,
        'app_id': '***',
        'app_key': '***',
      })}');

      final response = await http.get(uri);

      appLogger.d('📥 Edamam Response: HTTP ${response.statusCode}');
      appLogger.d('   Body: ${response.body}');

      if (response.statusCode != 200) {
        appLogger.e('❌ Edamam HTTP ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final hints = (json['hints'] as List?) ?? [];

      final results = hints
          .take(limit)
          .map((h) => _parseHint(h as Map<String, dynamic>))
          .whereType<FoodItem>()
          .toList();

      appLogger.i('🔍 Edamam "$query": ${hints.length} Treffer, ${results.length} mit Nährwerten');
      return results;
    } catch (e) {
      appLogger.e('❌ Edamam Suche fehlgeschlagen: $e');
      return [];
    }
  }

  FoodItem? _parseHint(Map<String, dynamic> hint) {
    try {
      final food = hint['food'] as Map<String, dynamic>?;
      if (food == null) return null;

      final name = (food['label'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;

      final nutrients = (food['nutrients'] as Map<String, dynamic>?) ?? {};

      final calories = _num(nutrients, 'ENERC_KCAL');
      if (calories == null) return null;

      final now = DateTime.now();

      return FoodItem(
        id: '',
        userId: null,
        name: name,
        calories: calories,
        protein: _num(nutrients, 'PROCNT') ?? 0.0,
        fat: _num(nutrients, 'FAT') ?? 0.0,
        carbs: _num(nutrients, 'CHOCDF') ?? 0.0,
        fiber: _num(nutrients, 'FIBTG'),
        sugar: _num(nutrients, 'SUGAR'),
        sodium: _num(nutrients, 'NA') != null
            ? _num(nutrients, 'NA')! / 1000  // mg → g
            : null,
        category: food['category'] as String?,
        brand: (food['brand'] as String?)?.isNotEmpty == true
            ? food['brand'] as String
            : null,
        barcode: null,
        source: 'Edamam',
        isPublic: false,
        isApproved: false,
        createdAt: now,
        updatedAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  double? _num(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
