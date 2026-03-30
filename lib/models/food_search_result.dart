import 'food_item.dart';

/// Ergebnis einer Online-Nahrungsmittelsuche (OFF, USDA).
///
/// Enthält das [FoodItem] sowie optional Mikronährstoffe pro 100 g
/// aus der API-Antwort. Schlüssel von [micros] entsprechen den
/// DB-Spaltennamen der Tabelle `food_entry_micros`
/// (z. B. `'vitamin_a_mcg'`, `'calcium_mg'`).
class FoodSearchResult {
  final FoodItem food;

  /// Mikronährstoffe pro 100 g. Leer wenn die Quelle keine Daten liefert.
  final Map<String, double> micros;

  const FoodSearchResult({required this.food, this.micros = const {}});

  bool get hasMicros => micros.isNotEmpty;
}
