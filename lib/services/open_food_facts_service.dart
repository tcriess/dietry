import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dietry/services/app_logger.dart';
import '../models/food_item.dart';
import '../models/food_portion.dart';
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
          .map((p) => parseProduct(p as Map<String, dynamic>, locale: locale))
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

      return parseProduct(product, locale: locale);
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
    // serving_quantity + nutrition_data_per are what say whether the numbers in
    // the *_100g fields really are per 100 g — see [_basisOf].
    return 'code,product_name,$localeName,brands,quantity,serving_size,'
        'serving_quantity,serving_quantity_unit,nutrition_data_per,'
        'nutriments,categories_tags';
  }

  /// Turns one OFF product record into a [FoodSearchResult], or null when it
  /// carries no usable nutrition — see the basis handling below for the second
  /// reason a record is refused.
  @visibleForTesting
  FoodSearchResult? parseProduct(Map<String, dynamic> p,
      {String locale = 'de'}) {
    try {
      final lc = locale.split('_').first.toLowerCase();
      final localeName = p['product_name_$lc'] as String?;
      final name = (localeName?.trim().isNotEmpty == true)
          ? localeName!
          : (p['product_name'] as String?)?.trim() ?? '';

      if (name.isEmpty) return null;

      final n = (p['nutriments'] as Map<String, dynamic>?) ?? {};

      // Which basis the contributor transcribed the label on. A per-serving
      // entry leaves the *_100g fields either converted by OFF (when it knows
      // what a serving weighs) or, when it does not, holding the per-serving
      // figures verbatim — importing those as per-100 g would log a 25 g bar at
      // a quarter of its calories. Refuse what cannot be resolved rather than
      // store a number whose basis we do not know.
      final serving = _servingGrams(p);
      final perServing = _basisOf(p) == 'serving';
      if (perServing && serving == null) {
        appLogger.w('⚠️ OFF "$name": Werte pro Portion, '
            'Portionsgewicht unbekannt — übersprungen');
        return null;
      }

      /// Nutrient [key] per 100 g/ml, whatever basis it was entered on.
      double? per100(String key) {
        final direct = _num(n, '${key}_100g');
        if (!perServing || direct != null) return direct;
        // OFF could not convert it for us — do it ourselves.
        final raw = _num(n, '${key}_serving') ?? _num(n, '${key}_value');
        return raw == null ? null : raw * 100 / serving!;
      }

      final calories = per100('energy-kcal') ??
          (per100('energy') != null
              ? per100('energy')! / 4.184 // kJ → kcal
              : null);

      if (calories == null) return null; // Ohne Kalorien nicht sinnvoll

      final protein = per100('proteins') ?? 0.0;
      final fat = per100('fat') ?? 0.0;
      final carbs = per100('carbohydrates') ?? 0.0;
      final fiber = per100('fiber');

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
        fiber: fiber,
        sugar: per100('sugars'),
        sodium: _saltPer100g(per100),
        saturatedFat: per100('saturated-fat'),
        category: category,
        brand: brand?.isNotEmpty == true ? brand : null,
        barcode: barcode?.isNotEmpty == true ? barcode : null,
        // The serving weight off the packet is exactly the portion the user
        // would otherwise have to measure and type in after scanning, so keep
        // it — both as the default amount and as a named portion to pick.
        servingSize: serving,
        servingUnit: serving == null ? null : _servingUnit(p),
        portions: serving == null
            ? const []
            : [FoodPortion(name: '1 Portion', amountG: serving)],
        source: 'OpenFoodFacts',
        isPublic: false,
        isApproved: false,
        createdAt: now,
        updatedAt: now,
      );

      return FoodSearchResult(
        food: food,
        micros: _extractMicros(n, per100),
        warnings: _implausibleValues(
          calories: calories,
          protein: protein,
          fat: fat,
          carbs: carbs,
          fiber: fiber,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// `nutrition_data_per` as OFF writes it: '100g' (the default and by far the
  /// common case), '100ml', 'serving', and occasionally '1kg'/'1l'. Only
  /// 'serving' needs handling — the rest already are a per-100 basis, and OFF
  /// normalizes them into the *_100g fields.
  String? _basisOf(Map<String, dynamic> p) =>
      (p['nutrition_data_per'] as String?)?.trim().toLowerCase();

  /// What one serving weighs, in g (or ml), or null when OFF does not know or
  /// states it in a unit we cannot convert. Servings under a gram are treated
  /// as unknown: extrapolating one to 100 g multiplies any typo by a hundred.
  double? _servingGrams(Map<String, dynamic> p) {
    final quantity = _num(p, 'serving_quantity');
    if (quantity == null || quantity < 1) return null;
    final unit = _servingUnit(p);
    return unit == null ? null : quantity;
  }

  /// 'g' or 'ml' for a serving we can use, null for anything else. OFF
  /// normalizes serving_quantity into one of the two and omits the unit for
  /// older rows, where grams is the right assumption.
  String? _servingUnit(Map<String, dynamic> p) {
    final raw =
        (p['serving_quantity_unit'] as String?)?.trim().toLowerCase() ?? 'g';
    return (raw == 'g' || raw == 'ml') ? raw : null;
  }

  /// Arithmetic sanity checks on the per-100 g values a community database
  /// hands us.
  ///
  /// These catch a value entered in the wrong unit or the wrong column — not a
  /// label transcribed wholesale on the wrong basis (a 25 g bar's figures typed
  /// into the per-100 g column stays consistent with itself and passes every
  /// check here). That case is only visible to someone holding the packet,
  /// which is why the log dialogs state the per-100 g basis they scale from.
  List<NutritionDataWarning> _implausibleValues({
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    double? fiber,
  }) {
    final warnings = <NutritionDataWarning>[];

    // 100 g of food cannot hold more than 100 g of macros, and cannot carry
    // more energy than the same weight of pure fat (900 kcal). A little slack
    // for rounding and for polyols counted twice.
    final mass = protein + fat + carbs + (fiber ?? 0);
    if (mass > 105 || calories > 950) {
      warnings.add(NutritionDataWarning.impossibleValues);
    }

    // Atwater: 4 kcal/g protein and carbs, 9 for fat, ~2 for fiber. Checked
    // only where there is enough energy for the comparison to mean anything,
    // and with wide bounds — polyols, alcohol and rounding all move it.
    final expected = 4 * protein + 9 * fat + 4 * carbs + 2 * (fiber ?? 0);
    if (expected >= 50 &&
        (calories < expected * 0.7 || calories > expected * 1.4)) {
      warnings.add(NutritionDataWarning.energyMismatch);
    }

    return warnings;
  }

  /// Extrahiert Mikronährstoffe aus dem OFF `nutriments`-Objekt.
  ///
  /// Normalisiert Einheiten auf die DB-Zieleinheiten:
  ///   g → mg (×1000), g → µg (×1,000,000), mg → µg (×1000).
  /// IU-Werte werden übersprungen.
  ///
  /// [per100] resolves a nutrient onto the per-100 g basis, so micronutrients
  /// follow the same basis correction as the macros — see [parseProduct].
  Map<String, double> _extractMicros(
      Map<String, dynamic> n, double? Function(String key) per100) {
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
      // Fettsäuren — gesättigtes Fett ist ein Kern-Feld (FoodItem.saturatedFat),
      // wird daher NICHT als Mikronährstoff dupliziert.
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
      final raw = per100(offKey);
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

  /// Salt per 100 g/ml. The app's `sodium` column stores SALT — OFF provides
  /// `salt_100g` directly (in grams); when only `sodium_100g` is present we
  /// derive salt as sodium × 2.5.
  double? _saltPer100g(double? Function(String key) per100) {
    final salt = per100('salt');
    if (salt != null) return salt;
    final sodium = per100('sodium');
    return sodium != null ? sodium * 2.5 : null;
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
