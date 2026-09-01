import '../models/food_item.dart';
import '../models/food_search_result.dart';
import 'food_database_service.dart';
import 'open_food_facts_service.dart';
import 'app_logger.dart';

class BarcodeLookupResult {
  final FoodItem food;
  final bool fromOff;
  final Map<String, double> micros;

  /// What looks wrong about [food]'s values, when it came from an online
  /// source. Always empty for a hit in the app's own database — those have
  /// been through this check already, or were entered by the user.
  final List<NutritionDataWarning> warnings;

  const BarcodeLookupResult({
    required this.food,
    required this.fromOff,
    this.micros = const {},
    this.warnings = const [],
  });
}

class BarcodeLookupService {
  /// Looks up [barcode] in the local food database first, then Open Food Facts.
  /// Returns null if the barcode is not found anywhere.
  static Future<BarcodeLookupResult?> lookup(
    String barcode, {
    FoodDatabaseService? dbService,
    String locale = 'de',
  }) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    if (dbService != null) {
      try {
        final local = await dbService.searchByBarcode(trimmed);
        if (local != null) {
          appLogger.i('✅ Barcode $trimmed in lokaler DB: ${local.name}');
          return BarcodeLookupResult(food: local, fromOff: false);
        }
      } catch (e) {
        appLogger.w('⚠️ Lokale Barcode-Suche fehlgeschlagen: $e');
      }
    }

    try {
      final off = await OpenFoodFactsService().searchByBarcode(trimmed, locale: locale);
      if (off != null) {
        appLogger.i('✅ Barcode $trimmed bei Open Food Facts: ${off.food.name}');
        return BarcodeLookupResult(
          food: off.food,
          fromOff: true,
          micros: off.micros,
          warnings: off.warnings,
        );
      }
    } catch (e) {
      appLogger.w('⚠️ OFF Barcode-Suche fehlgeschlagen: $e');
    }

    appLogger.i('ℹ️ Barcode $trimmed nicht gefunden');
    return null;
  }
}
