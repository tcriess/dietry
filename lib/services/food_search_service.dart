import '../app_config.dart';
import '../models/food_search_result.dart';
import 'usda_service.dart';
import 'open_food_facts_service.dart';

/// Kombinierte Online-Suche: USDA FoodData Central + Open Food Facts.
///
/// Strategie:
/// - Mit USDA-Key (alle Plattformen): USDA + OFF parallel, USDA-Ergebnisse zuerst
/// - Ohne USDA-Key: nur OFF
///
/// Attributionspflicht:
/// - USDA: "Data sourced from USDA FoodData Central" (empfohlen)
/// - OFF:  "Data from Open Food Facts (openfoodfacts.org)" (ODbL, Pflicht)
class FoodSearchService {
  final _usda = UsdaService();
  final _off = OpenFoodFactsService();

  /// True wenn mindestens eine Online-Quelle verfügbar ist.
  static bool get isAvailable => true; // OFF ist immer verfügbar

  /// [locale] bestimmt bevorzugte Sprache für OFF-Produktnamen (z.B. 'de', 'en', 'es').
  Future<List<FoodSearchResult>> search(String query,
      {int limit = 20, String locale = 'de'}) async {
    if (query.trim().isEmpty) return [];

    // Mit USDA-Key: beide parallel abfragen (alle Plattformen inkl. Web)
    if (AppConfig.hasUsda) {
      final results = await Future.wait([
        _usda.searchByName(query, limit: limit),
        _off.searchByName(query, limit: limit ~/ 2, locale: locale),
      ]);
      // USDA zuerst, OFF danach; Gesamt auf limit begrenzen
      return [...results[0], ...results[1]].take(limit).toList();
    }

    // Kein USDA-Key: nur OFF
    return _off.searchByName(query, limit: limit, locale: locale);
  }
}
