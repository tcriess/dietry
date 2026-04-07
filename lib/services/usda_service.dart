import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dietry/services/app_logger.dart';
import '../app_config.dart';
import '../models/food_item.dart';
import '../models/food_search_result.dart';

/// Nährwertsuche via USDA FoodData Central API.
///
/// Kostenlos, kein Rate Limit-Problem (1000 req/h).
/// API-Key kostenlos unter https://api.data.gov/signup/
///
/// Attribution (empfohlen): "Data sourced from USDA FoodData Central"
/// Docs: https://fdc.nal.usda.gov/api-guide.html
class UsdaService {
  static const String _baseUrl = 'https://api.nal.usda.gov/fdc/v1/foods/search';

  Future<List<FoodSearchResult>> searchByName(String query,
      {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    if (!AppConfig.hasUsda) return [];

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'api_key': AppConfig.usdaApiKey,
        'query': query,
        'pageSize': limit.toString(),
        // Foundation + SR Legacy: zuverlässige per-100g Nährwerte
        // Branded: Markenprodukte (internationale Abdeckung)
        'dataType': 'Foundation,SR Legacy,Branded',
      });

      // Key aus Log heraushalten
      final logUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'api_key': '***',
      });
      appLogger.d('🌐 USDA Request: GET $logUri');

      final response = await http.get(uri);

      appLogger.d('📥 USDA Response: HTTP ${response.statusCode}');
      if (response.statusCode != 200) {
        appLogger.e('❌ USDA Fehler: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final foods = (json['foods'] as List?) ?? [];

      final results = foods
          .map((f) => _parseFood(f as Map<String, dynamic>))
          .whereType<FoodSearchResult>()
          .toList();

      appLogger.d('🔍 USDA "$query": ${foods.length} Treffer, ${results.length} mit Nährwerten');
      return results;
    } catch (e) {
      appLogger.e('❌ USDA Suche fehlgeschlagen: $e');
      return [];
    }
  }

  FoodSearchResult? _parseFood(Map<String, dynamic> f) {
    try {
      final description = (f['description'] as String?)?.trim() ?? '';
      if (description.isEmpty) return null;

      // Nährwerte als Map aufbauen (Name → {value, unit})
      final nutrients = <String, double>{};
      final units = <String, String>{}; // nutrientName → unitName
      for (final n in (f['foodNutrients'] as List? ?? [])) {
        final name = n['nutrientName'] as String? ?? '';
        final value = n['value'];
        final unit = (n['unitName'] as String? ?? '').toUpperCase();
        if (value is num) {
          nutrients[name] = value.toDouble();
          units[name] = unit;
        }
      }

      // Kalorien: "Energy" in kcal (manche Einträge haben kJ, kcal bevorzugen)
      final calories = nutrients['Energy'] ??
          (nutrients.entries
                  .where((e) =>
                      e.key.startsWith('Energy') &&
                      (f['foodNutrients'] as List? ?? []).any((n) =>
                          n['nutrientName'] == e.key &&
                          (n['unitName'] as String? ?? '') == 'kcal'))
                  .map((e) => e.value)
                  .firstOrNull);
      if (calories == null) return null;

      final brand = (f['brandOwner'] as String?)?.trim();
      final category = (f['foodCategory'] as String?)?.trim();
      final now = DateTime.now();

      final food = FoodItem(
        id: '',
        userId: null,
        name: description,
        calories: calories,
        protein: nutrients['Protein'] ?? 0.0,
        fat: nutrients['Total lipid (fat)'] ?? 0.0,
        carbs: nutrients['Carbohydrate, by difference'] ?? 0.0,
        fiber: nutrients['Fiber, total dietary'],
        sugar: nutrients['Sugars, total including NLEA'] ?? nutrients['Sugars, Total'],
        // USDA gibt Natrium in mg, FoodItem erwartet g
        sodium: nutrients['Sodium, Na'] != null
            ? nutrients['Sodium, Na']! / 1000
            : null,
        category: category?.isNotEmpty == true ? category : null,
        brand: brand?.isNotEmpty == true ? brand : null,
        barcode: null,
        portions: const [],
        source: 'USDA',
        isPublic: false,
        isApproved: false,
        createdAt: now,
        updatedAt: now,
      );

      return FoodSearchResult(
        food: food,
        micros: _extractMicros(nutrients, units),
      );
    } catch (_) {
      return null;
    }
  }

  /// Extrahiert Mikronährstoffe aus der USDA `foodNutrients`-Liste.
  ///
  /// USDA liefert Werte per 100 g für Foundation/SR Legacy.
  /// Mapping: USDA-Nährstoffname + API-Einheit → DB-Spaltenname.
  Map<String, double> _extractMicros(
      Map<String, double> nutrients, Map<String, String> units) {
    // (usda_name, db_spalte, erwartete_einheit: 'G'|'MG'|'UG')
    // Die Einheit dient zur Prüfung — USDA ist für diese Felder konsistent.
    const mapping = [
      // Vitamine – fettlöslich
      ('Vitamin A, RAE',                    'vitamin_a_mcg',         'UG'),
      ('Vitamin D (D2 + D3)',               'vitamin_d_mcg',         'UG'),
      ('Vitamin D (D2 + D3), International Units', 'vitamin_d_iu',  'IU'), // wird ignoriert
      ('Vitamin E (alpha-tocopherol)',       'vitamin_e_mg',          'MG'),
      ('Vitamin K (phylloquinone)',          'vitamin_k_mcg',         'UG'),
      ('Vitamin K1',                        'vitamin_k_mcg',         'UG'),
      // Vitamine – wasserlöslich
      ('Vitamin C, total ascorbic acid',    'vitamin_c_mg',          'MG'),
      ('Thiamin',                           'vitamin_b1_mg',         'MG'),
      ('Riboflavin',                        'vitamin_b2_mg',         'MG'),
      ('Niacin',                            'vitamin_b3_mg',         'MG'),
      ('Pantothenic acid',                  'vitamin_b5_mg',         'MG'),
      ('Vitamin B-6',                       'vitamin_b6_mg',         'MG'),
      ('Biotin',                            'vitamin_b7_mcg',        'UG'),
      ('Folate, total',                     'vitamin_b9_mcg',        'UG'),
      ('Folate, DFE',                       'vitamin_b9_mcg',        'UG'),
      ('Vitamin B-12',                      'vitamin_b12_mcg',       'UG'),
      // Mineralstoffe
      ('Calcium, Ca',                       'calcium_mg',            'MG'),
      ('Iron, Fe',                          'iron_mg',               'MG'),
      ('Magnesium, Mg',                     'magnesium_mg',          'MG'),
      ('Phosphorus, P',                     'phosphorus_mg',         'MG'),
      ('Potassium, K',                      'potassium_mg',          'MG'),
      ('Zinc, Zn',                          'zinc_mg',               'MG'),
      ('Selenium, Se',                      'selenium_mcg',          'UG'),
      ('Iodine, I',                         'iodine_mcg',            'UG'),
      ('Manganese, Mn',                     'manganese_mg',          'MG'),
      ('Copper, Cu',                        'copper_mg',             'MG'),
      // Fettsäuren
      ('Fatty acids, total saturated',      'saturated_fat_g',       'G'),
      ('Fatty acids, total monounsaturated','monounsaturated_fat_g', 'G'),
      ('Fatty acids, total polyunsaturated','polyunsaturated_fat_g', 'G'),
      ('Fatty acids, total trans',          'trans_fat_g',           'G'),
      ('Cholesterol',                       'cholesterol_mg',        'MG'),
    ];

    final result = <String, double>{};

    for (final (usdaName, dbCol, expectedUnit) in mapping) {
      if (dbCol == 'vitamin_d_iu') continue; // IU-Variante überspringen

      final value = nutrients[usdaName];
      if (value == null || value < 0) continue;

      final actualUnit = units[usdaName] ?? expectedUnit;

      // Einheit zur Sicherheit konvertieren falls abweichend
      final converted = _convertUnit(value,
          fromUsda: actualUnit, toUsda: expectedUnit);
      if (converted == null) continue;

      // Kein Überschreiben wenn bereits ein anderer Name für dieselbe Spalte gesetzt
      if (!result.containsKey(dbCol)) {
        result[dbCol] = converted;
      }
    }

    return result;
  }

  /// Konvertiert USDA-Einheiten ('G', 'MG', 'UG').
  static double? _convertUnit(double value,
      {required String fromUsda, required String toUsda}) {
    if (fromUsda == toUsda) return value;
    if (fromUsda == 'G' && toUsda == 'MG') return value * 1000;
    if (fromUsda == 'G' && toUsda == 'UG') return value * 1000000;
    if (fromUsda == 'MG' && toUsda == 'G') return value / 1000;
    if (fromUsda == 'MG' && toUsda == 'UG') return value * 1000;
    if (fromUsda == 'UG' && toUsda == 'G') return value / 1000000;
    if (fromUsda == 'UG' && toUsda == 'MG') return value / 1000;
    return null;
  }
}
