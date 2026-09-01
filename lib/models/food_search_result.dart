import 'food_item.dart';

/// Was an online source's nutrition values look wrong about.
///
/// Community-maintained databases carry transcription mistakes, and the values
/// land in the app's own food database unchanged. These are the cases arithmetic
/// alone can catch — a uniformly mis-scaled label (per-portion figures typed
/// into the per-100 g column) stays self-consistent and is not among them.
enum NutritionDataWarning {
  /// Physically impossible per 100 g: macros weighing more than 100 g, or more
  /// energy than pure fat can carry.
  impossibleValues,

  /// The declared energy does not match what the macros add up to (Atwater
  /// 4/9/4), so at least one of the two was entered wrong.
  energyMismatch,
}

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

  /// What looks wrong about [food]'s nutrition values, if anything. Empty for
  /// the ordinary case; the UI warns before the food is logged or stored.
  final List<NutritionDataWarning> warnings;

  const FoodSearchResult({
    required this.food,
    this.micros = const {},
    this.warnings = const [],
  });

  bool get hasMicros => micros.isNotEmpty;
}
