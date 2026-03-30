// Dietry Cloud Edition — Community Stubs
//
// Dieses Package enthält ausschließlich No-Op-Implementierungen aller
// Cloud-Features. In der Cloud-Edition wird dieses Package via
// `dependency_overrides` in pubspec.yaml durch die echte Implementierung
// aus dem privaten Repository ersetzt:
//
//   dependency_overrides:
//     dietry_cloud:
//       git:
//         url: git@github.com:yourorg/dietry-cloud.git
//         ref: main
//
// Die echte Implementierung setzt [premiumFeatures] beim Package-Import
// auf eine [_RealPremiumFeatures]-Instanz.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

// ── Typen für Callbacks ───────────────────────────────────────────────────────

/// Suchresultat für die Zutatensuche im Mahlzeiten-Vorlagen-Editor.
/// Definiert hier im Stub um zirkuläre Paket-Abhängigkeiten zu vermeiden.
class MealIngredientCandidate {
  final String? id;
  final String name;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;
  final String? source;
  final List<({String name, double weightG})> portions;

  const MealIngredientCandidate({
    this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    this.source,
    this.portions = const [],
  });

  bool get isOnlineOnly => id == null || id!.isEmpty;
}

/// Daten die beim Eintragen einer Mahlzeiten-Vorlage übergeben werden.
/// Enthält alle Felder die für einen FoodEntry benötigt werden.
/// Verwendet primitive Typen um zirkuläre Paket-Abhängigkeiten zu vermeiden.
/// Daten für den Aktivitäts-Schnelleintrag-Callback.
class ActivityQuickAddData {
  final String activityType;
  final String? activityId;
  final String? activityName;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final double? caloriesBurned;
  final double? distanceKm;

  const ActivityQuickAddData({
    required this.activityType,
    this.activityId,
    this.activityName,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.caloriesBurned,
    this.distanceKm,
  });
}

class MealTemplateLogData {
  final String name;
  final double amount;
  final String unit;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;

  /// Mahlzeit-Typ als String: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  final String mealType;

  const MealTemplateLogData({
    required this.name,
    required this.amount,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
    required this.mealType,
  });
}

// ── Globale Instanz ───────────────────────────────────────────────────────────

/// Globale Premium-Feature-Instanz.
/// Community Edition: [NullPremiumFeatures] (No-Ops).
/// Cloud Edition: wird beim Package-Import auf echte Implementierung gesetzt.
PremiumFeatures premiumFeatures = const NullPremiumFeatures();

/// Registriert die Premium-Implementierung.
/// Wird vom privaten Premium-Package beim App-Start aufgerufen.
void registerPremiumFeatures(PremiumFeatures implementation) {
  premiumFeatures = implementation;
}

// ── Abstract Interface ────────────────────────────────────────────────────────

/// Definiert alle Premium-Features als abstrakte Schnittstelle.
/// Neue Features werden hier als abstrakte Methoden ergänzt —
/// gleichzeitig im Stub (No-Op) und in der echten Implementierung.
abstract class PremiumFeatures {
  const PremiumFeatures();

  bool get isAvailable;

  // ── Mahlzeiten-Vorlagen ───────────────────────────────────────────────────

  bool get hasMealTemplates;

  Widget buildMealTemplatesSheet({
    required String userId,
    required DateTime date,
    required String authToken,
    required String dataApiUrl,
    required Future<void> Function(MealTemplateLogData data) onLog,
    Future<List<MealIngredientCandidate>> Function(String query, {bool searchOnline})? onSearchIngredient,
  });

  // ── Mikronährstoffe ───────────────────────────────────────────────────────

  bool get hasMicroNutrients;

  Widget buildMicroOverviewCard({
    required List<String> entryIds,
    required String userId,
    required String authToken,
    required String apiUrl,
  });

  void showMicroNutrientsSheet({
    required BuildContext context,
    required String entryId,
    required String entryName,
    required String userId,
    required String authToken,
    required String apiUrl,
  });

  void showFoodDatabaseMicrosSheet({
    required BuildContext context,
    required String foodId,
    required String foodName,
    required String userId,
    required String authToken,
    required String apiUrl,
  });

  Future<void> copyFoodMicrosToEntry({
    required String foodId,
    required String entryId,
    required String userId,
    required double amountG,
    required String authToken,
    required String apiUrl,
  });

  void showActivityQuickAddSheet({
    required BuildContext context,
    required String userId,
    required String authToken,
    required String apiUrl,
    required DateTime date,
    required Future<void> Function(ActivityQuickAddData) onAdd,
  });

  /// Speichert Mikronährstoffe eines Food-Entries aus einer Karte (per 100 g).
  /// Wird für Ergebnisse aus OFF/USDA verwendet, die (noch) kein food_database-Eintrag haben.
  /// [micros100g] Schlüssel = DB-Spaltennamen (z.B. 'vitamin_a_mcg').
  /// [amountG] ist die tatsächliche Menge in Gramm zum Skalieren.
  /// Best-effort — wirft keine Exception bei Fehlern.
  Future<void> saveFoodEntryMicrosFromMap({
    required String entryId,
    required String userId,
    required Map<String, double> micros100g,
    required double amountG,
    required String authToken,
    required String apiUrl,
  });
}

// ── No-Op Implementierung (Community Edition) ─────────────────────────────────

class NullPremiumFeatures implements PremiumFeatures {
  const NullPremiumFeatures();

  @override bool get isAvailable => false;
  @override bool get hasMealTemplates => false;
  @override bool get hasMicroNutrients => false;

  @override
  Widget buildMicroOverviewCard({
    required List<String> entryIds,
    required String userId,
    required String authToken,
    required String apiUrl,
  }) =>
      const SizedBox.shrink();

  @override
  Widget buildMealTemplatesSheet({
    required String userId,
    required DateTime date,
    required String authToken,
    required String dataApiUrl,
    required Future<void> Function(MealTemplateLogData data) onLog,
    Future<List<MealIngredientCandidate>> Function(String query, {bool searchOnline})? onSearchIngredient,
  }) =>
      const SizedBox.shrink();

  @override
  void showMicroNutrientsSheet({
    required BuildContext context,
    required String entryId,
    required String entryName,
    required String userId,
    required String authToken,
    required String apiUrl,
  }) {}

  @override
  void showFoodDatabaseMicrosSheet({
    required BuildContext context,
    required String foodId,
    required String foodName,
    required String userId,
    required String authToken,
    required String apiUrl,
  }) {}

  @override
  Future<void> copyFoodMicrosToEntry({
    required String foodId,
    required String entryId,
    required String userId,
    required double amountG,
    required String authToken,
    required String apiUrl,
  }) async {}

  @override
  void showActivityQuickAddSheet({
    required BuildContext context,
    required String userId,
    required String authToken,
    required String apiUrl,
    required DateTime date,
    required Future<void> Function(ActivityQuickAddData) onAdd,
  }) {}

  @override
  Future<void> saveFoodEntryMicrosFromMap({
    required String entryId,
    required String userId,
    required Map<String, double> micros100g,
    required double amountG,
    required String authToken,
    required String apiUrl,
  }) async {}
}
