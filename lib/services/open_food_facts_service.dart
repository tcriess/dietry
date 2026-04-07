import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dietry/services/app_logger.dart';
import '../models/food_item.dart';
import '../models/food_search_result.dart';

/// Sucht Nährwertinformationen über die Open Food Facts API.
///
/// Open Food Facts ist eine freie, öffentliche Datenbank (keine API-Keys
/// erforderlich). Die Ergebnisse werden als [FoodSearchResult]-Objekte
/// zurückgegeben und können direkt in der App weiterverwendet werden.
///
/// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
class OpenFoodFactsService {
  static const String _baseUrl = 'https://world.openfoodfacts.org';
  static const String _userAgent = 'Dietry/1.0 (Flutter)';

  /// Suche nach Produkten via Freitext.
  ///
  /// Gibt bis zu [limit] Ergebnisse zurück, die Nährwertangaben enthalten.
  /// [locale] bestimmt bevorzugte Sprache für Produktnamen (z.B. 'de', 'en', 'es').
  Future<List<FoodSearchResult>> searchByName(String query,
      {int limit = 20, String locale = 'de'}) async {
    if (query.trim().isEmpty) return [];

    try {
      final fields = _fieldsForLocale(locale);
      final uri = Uri.parse('$_baseUrl/api/v2/search').replace(
        queryParameters: {
          'q': query,
          'page_size': limit.toString(),
          'fields': fields,
        },
      );

      appLogger.d('🌐 OFF Request: GET $uri');
      appLogger.d('   Headers: {User-Agent: $_userAgent}');

      final response = await http.get(uri, headers: {'User-Agent': _userAgent});

      appLogger.d('📥 OFF Response: HTTP ${response.statusCode}');
      appLogger.d('   Response-Headers: ${response.headers}');
      appLogger.d('   Body: ${response.body}');

      if (response.statusCode != 200) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final products = (json['products'] as List?) ?? [];

      final parsed = products
          .map((p) => _parseProduct(p as Map<String, dynamic>, locale: locale))
          .whereType<FoodSearchResult>()
          .toList();

      appLogger.d('🔍 OFF "$query": ${products.length} Produkte, ${parsed.length} mit Nährwerten');
      return parsed;
    } catch (e) {
      appLogger.e('❌ Open Food Facts Suche fehlgeschlagen: $e');
      return [];
    }
  }

  /// Suche Produkt via Barcode (EAN-13 / EAN-8 / UPC).
  Future<FoodSearchResult?> searchByBarcode(String barcode,
      {String locale = 'de'}) async {
    if (barcode.trim().isEmpty) return null;

    try {
      final fields = _fieldsForLocale(locale);
      final uri = Uri.parse(
        '$_baseUrl/api/v2/product/$barcode.json?fields=$fields',
      );

      final response = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 1) return null; // Produkt nicht gefunden

      final product = json['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      return _parseProduct(product, locale: locale);
    } catch (e) {
      appLogger.e('❌ Open Food Facts Barcode-Suche fehlgeschlagen: $e');
      return null;
    }
  }

  // ── Interna ───────────────────────────────────────────────────────────────

  static String _fieldsForLocale(String locale) {
    final lc = locale.split('_').first.toLowerCase();
    // Always include generic + locale-specific name field
    final localeName = 'product_name_$lc';
    return 'code,product_name,$localeName,brands,quantity,serving_size,'
        'nutriments,categories_tags';
  }

  FoodSearchResult? _parseProduct(Map<String, dynamic> p,
      {String locale = 'de'}) {
    try {
      final lc = locale.split('_').first.toLowerCase();
      final localeName = p['product_name_$lc'] as String?;
      final name = (localeName?.trim().isNotEmpty == true)
          ? localeName!
          : (p['product_name'] as String?)?.trim() ?? '';

      if (name.isEmpty) return null;

      final n = (p['nutriments'] as Map<String, dynamic>?) ?? {};

      final calories = _num(n, 'energy-kcal_100g') ??
          (_num(n, 'energy_100g') != null
              ? _num(n, 'energy_100g')! / 4.184 // kJ → kcal
              : null);

      if (calories == null) return null; // Ohne Kalorien nicht sinnvoll

      final protein = _num(n, 'proteins_100g') ?? 0.0;
      final fat = _num(n, 'fat_100g') ?? 0.0;
      final carbs = _num(n, 'carbohydrates_100g') ?? 0.0;

      final barcode = (p['code'] as String?)?.trim();
      final brand = _parseBrand(p['brands']);
      final category = _mapCategory(p['categories_tags']);

      final now = DateTime.now();

      final food = FoodItem(
        id: '', // Wird beim Speichern in der DB vergeben
        userId: null,
        name: name,
        calories: calories,
        protein: protein,
        fat: fat,
        carbs: carbs,
        fiber: _num(n, 'fiber_100g'),
        sugar: _num(n, 'sugars_100g'),
        sodium: _num(n, 'sodium_100g'),
        category: category,
        brand: brand?.isNotEmpty == true ? brand : null,
        barcode: barcode?.isNotEmpty == true ? barcode : null,
        portions: const [],
        source: 'OpenFoodFacts',
        isPublic: false,
        isApproved: false,
        createdAt: now,
        updatedAt: now,
      );

      return FoodSearchResult(food: food, micros: _extractMicros(n));
    } catch (_) {
      return null;
    }
  }

  /// Extrahiert Mikronährstoffe aus dem OFF `nutriments`-Objekt.
  ///
  /// Normalisiert Einheiten auf die DB-Zieleinheiten:
  ///   g → mg (×1000), g → µg (×1,000,000), mg → µg (×1000).
  /// IU-Werte werden übersprungen.
  Map<String, double> _extractMicros(Map<String, dynamic> n) {
    // (off_key_präfix, db_spalte, ziel_einheit: 'g'|'mg'|'mcg')
    const mapping = [
      // Vitamine – fettlöslich
      ('vitamin-a',          'vitamin_a_mcg',           'mcg'),
      ('vitamin-d',          'vitamin_d_mcg',           'mcg'),
      ('vitamin-e',          'vitamin_e_mg',            'mg'),
      ('vitamin-k',          'vitamin_k_mcg',           'mcg'),
      // Vitamine – wasserlöslich
      ('vitamin-c',          'vitamin_c_mg',            'mg'),
      ('vitamin-b1',         'vitamin_b1_mg',           'mg'),
      ('vitamin-b2',         'vitamin_b2_mg',           'mg'),
      ('vitamin-b3',         'vitamin_b3_mg',           'mg'),
      ('vitamin-pp',         'vitamin_b3_mg',           'mg'), // Niacin-Alias
      ('vitamin-b5',         'vitamin_b5_mg',           'mg'),
      ('pantothenic-acid',   'vitamin_b5_mg',           'mg'),
      ('vitamin-b6',         'vitamin_b6_mg',           'mg'),
      ('vitamin-b7',         'vitamin_b7_mcg',          'mcg'),
      ('biotin',             'vitamin_b7_mcg',          'mcg'),
      ('vitamin-b9',         'vitamin_b9_mcg',          'mcg'),
      ('folates',            'vitamin_b9_mcg',          'mcg'),
      ('vitamin-b12',        'vitamin_b12_mcg',         'mcg'),
      // Mineralstoffe
      ('calcium',            'calcium_mg',              'mg'),
      ('iron',               'iron_mg',                 'mg'),
      ('magnesium',          'magnesium_mg',            'mg'),
      ('phosphorus',         'phosphorus_mg',           'mg'),
      ('potassium',          'potassium_mg',            'mg'),
      ('zinc',               'zinc_mg',                 'mg'),
      ('selenium',           'selenium_mcg',            'mcg'),
      ('iodine',             'iodine_mcg',              'mcg'),
      ('manganese',          'manganese_mg',            'mg'),
      ('copper',             'copper_mg',               'mg'),
      // Fettsäuren
      ('saturated-fat',      'saturated_fat_g',         'g'),
      ('monounsaturated-fat','monounsaturated_fat_g',   'g'),
      ('polyunsaturated-fat','polyunsaturated_fat_g',   'g'),
      ('trans-fat',          'trans_fat_g',             'g'),
      ('omega-3-fat',        'omega_3_g',               'g'),
      ('omega-6-fat',        'omega_6_g',               'g'),
      ('cholesterol',        'cholesterol_mg',          'mg'),
    ];

    final result = <String, double>{};

    for (final (offKey, dbCol, targetUnit) in mapping) {
      // OFF-Schlüssel: '{prefix}_100g' und '{prefix}_unit'
      final raw = _num(n, '${offKey}_100g');
      if (raw == null || raw <= 0) continue;

      // Einheit normalisieren: IU ignorieren
      final unitRaw = (n['${offKey}_unit'] as String? ?? '').toLowerCase();
      final unit = unitRaw == 'µg' ? 'mcg' : unitRaw;
      if (unit == 'iu') continue; // IU nicht konvertierbar ohne Referenzwert

      final converted = _convertUnit(raw, from: unit, to: targetUnit);
      if (converted != null && !result.containsKey(dbCol)) {
        result[dbCol] = converted;
      }
    }

    return result;
  }

  /// Konvertiert [value] von [from]- in [to]-Einheit.
  /// Gibt null zurück wenn die Konvertierung unbekannt ist.
  static double? _convertUnit(double value,
      {required String from, required String to}) {
    if (from == to || from.isEmpty) return value;
    // g → mg
    if (from == 'g' && to == 'mg') return value * 1000;
    // g → mcg
    if (from == 'g' && to == 'mcg') return value * 1000000;
    // mg → g
    if (from == 'mg' && to == 'g') return value / 1000;
    // mg → mcg
    if (from == 'mg' && to == 'mcg') return value * 1000;
    // mcg → g
    if (from == 'mcg' && to == 'g') return value / 1000000;
    // mcg → mg
    if (from == 'mcg' && to == 'mg') return value / 1000;
    return null; // unbekannte Konvertierung
  }

  double? _num(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  String? _parseBrand(dynamic raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // Split by comma and take first brand
    final brand = trimmed.split(',').first.trim();
    return brand.isEmpty ? null : brand;
  }

  String? _mapCategory(dynamic tags) {
    if (tags is! List) return null;
    // Einfache Übersetzung der häufigsten Open Food Facts Kategorien
    const mapping = {
      'en:beverages': 'Getränke',
      'en:dairy': 'Milchprodukte',
      'en:meats': 'Fleisch',
      'en:fish': 'Fisch',
      'en:fruits': 'Obst',
      'en:vegetables': 'Gemüse',
      'en:breads': 'Brot & Backwaren',
      'en:cereals-and-potatoes': 'Getreide & Kartoffeln',
      'en:snacks': 'Snacks',
      'en:sweet-snacks': 'Süßigkeiten',
      'en:condiments': 'Würzmittel',
      'en:frozen-foods': 'Tiefkühlprodukte',
    };
    for (final tag in tags) {
      // Ensure tag is a string before using as map key
      if (tag is! String) continue;
      final category = mapping[tag];
      if (category != null) return category;
    }
    return null;
  }
}
