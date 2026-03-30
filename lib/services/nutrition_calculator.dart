import '../models/models.dart';

/// Service zur Berechnung des Kalorienbedarfs und Makronährstoff-Empfehlungen
/// 
/// Verwendet die Mifflin-St Jeor Formel (genauer als Harris-Benedict)
/// 
/// Unterstützt drei Tracking-Methoden:
/// - BMR-basiert: Alle Aktivitäten tracken
/// - TDEE komplett: Kaum Tracking nötig
/// - TDEE hybrid: Nur Sport tracken
class NutritionCalculator {
  /// Berechnet den Grundumsatz (BMR - Basal Metabolic Rate)
  /// 
  /// Mifflin-St Jeor Formel:
  /// Männer: BMR = (10 × Gewicht kg) + (6,25 × Größe cm) − (5 × Alter Jahre) + 5
  /// Frauen: BMR = (10 × Gewicht kg) + (6,25 × Größe cm) − (5 × Alter Jahre) − 161
  static double calculateBMR(UserBodyData data) {
    double bmr = (10 * data.weight) + (6.25 * data.height) - (5 * data.age);
    
    if (data.gender == Gender.male) {
      bmr += 5;
    } else {
      bmr -= 161;
    }
    
    return bmr;
  }

  /// Berechnet den Gesamtumsatz (TDEE - Total Daily Energy Expenditure)
  /// 
  /// TDEE = BMR × Aktivitätslevel-Multiplikator
  static double calculateTDEE(UserBodyData data) {
    final bmr = calculateBMR(data);
    return bmr * data.activityLevel.multiplier;
  }

  /// Berechnet Zielkalorien basierend auf Tracking-Methode
  /// 
  /// BMR-basiert: Verwendet nur BMR (Activity Level = 1.0)
  /// TDEE-basiert: Verwendet TDEE mit Activity Level
  /// 
  /// Dann wird Gewichtsziel-Adjustment angewendet:
  /// - Abnehmen: -500 kcal (ca. 0.5 kg/Woche)
  /// - Halten: ±0 kcal
  /// - Zunehmen: +300 kcal
  static double calculateTargetCalories(
    UserBodyData data, {
    TrackingMethod method = TrackingMethod.tdeeHybrid,
  }) {
    final bmr = calculateBMR(data);
    final double baseCalories;

    switch (method) {
      case TrackingMethod.bmrOnly:
        // Nur Grundumsatz, ALLE Aktivitäten müssen getrackt werden
        baseCalories = bmr;
        break;
      case TrackingMethod.tdeeComplete:
      case TrackingMethod.tdeeHybrid:
        // Gesamtumsatz mit Activity Level
        // Bei hybrid sollte Activity Level nur Alltag reflektieren
        baseCalories = bmr * data.activityLevel.multiplier;
        break;
    }

    return baseCalories + data.weightGoal.calorieAdjustment;
  }

  /// Berechnet Zielkalorien basierend auf Gewichtsziel (alte Methode für Kompatibilität)
  /// 
  /// @deprecated Verwende calculateTargetCalories mit TrackingMethod
  @Deprecated('Use calculateTargetCalories with TrackingMethod parameter')
  static double calculateTargetCaloriesLegacy(UserBodyData data) {
    return calculateTargetCalories(data, method: TrackingMethod.tdeeHybrid);
  }

  /// Berechnet Makronährstoff-Empfehlungen
  /// 
  /// Standard-Verteilung:
  /// - Protein: 2g/kg Körpergewicht (wichtig für Muskelerhalt)
  /// - Fett: 25-30% der Kalorien
  /// - Kohlenhydrate: Rest
  static MacroRecommendation calculateMacros(
    UserBodyData data, {
    TrackingMethod method = TrackingMethod.tdeeHybrid,
  }) {
    final bmr = calculateBMR(data);
    final tdee = calculateTDEE(data);
    final targetCalories = calculateTargetCalories(data, method: method);
    
    // Protein: 2g pro kg Körpergewicht
    final protein = data.weight * 2.0;
    
    // Fett: 25% der Kalorien (1g Fett = 9 kcal)
    final fatCalories = targetCalories * 0.25;
    final fat = fatCalories / 9;
    
    // Kohlenhydrate: Rest (1g Carbs = 4 kcal)
    final proteinCalories = protein * 4;
    final carbCalories = targetCalories - proteinCalories - fatCalories;
    final carbs = carbCalories / 4;
    
    return MacroRecommendation(
      calories: targetCalories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      bmr: bmr,
      tdee: tdee,
      method: method,
    );
  }

  /// Berechnet die empfohlene Wassermenge in ml (35 ml/kg, gerundet auf 250 ml)
  static int calculateWaterGoal(double weightKg) {
    final raw = weightKg * 35;
    final clamped = raw.clamp(1500, 3500);
    return ((clamped / 250).round() * 250).toInt();
  }

  /// Erstellt ein NutritionGoal aus den berechneten Empfehlungen
  static NutritionGoal createGoalFromRecommendation(MacroRecommendation recommendation) {
    return NutritionGoal(
      calories: recommendation.calories.roundToDouble(),
      protein: recommendation.protein.roundToDouble(),
      fat: recommendation.fat.roundToDouble(),
      carbs: recommendation.carbs.roundToDouble(),
      trackingMethod: recommendation.method,
    );
  }
}

/// Makronährstoff-Empfehlung
class MacroRecommendation {
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double bmr;   // Grundumsatz
  final double tdee;  // Gesamtumsatz
  final TrackingMethod method; // Verwendete Tracking-Methode

  MacroRecommendation({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.bmr,
    required this.tdee,
    required this.method,
  });

  /// Berechnet prozentuale Makro-Verteilung
  Map<String, double> get macroPercentages {
    final proteinCal = protein * 4;
    final fatCal = fat * 9;
    final carbsCal = carbs * 4;
    final total = proteinCal + fatCal + carbsCal;

    return {
      'protein': (proteinCal / total * 100),
      'fat': (fatCal / total * 100),
      'carbs': (carbsCal / total * 100),
    };
  }

  /// Zeigt Zusammenfassung der Berechnung
  String get summary {
    final buffer = StringBuffer();
    buffer.writeln('📊 Kalorienbedarf-Berechnung');
    buffer.writeln('');
    buffer.writeln('Methode: ${method.displayName}');
    buffer.writeln('');
    buffer.writeln('Grundumsatz (BMR): ${bmr.round()} kcal');
    buffer.writeln('Gesamtumsatz (TDEE): ${tdee.round()} kcal');
    buffer.writeln('');
    buffer.writeln('🎯 Dein Ziel: ${calories.round()} kcal/Tag');
    buffer.writeln('');
    buffer.writeln('Makros:');
    buffer.writeln('• Protein: ${protein.round()}g (${macroPercentages['protein']!.round()}%)');
    buffer.writeln('• Fett: ${fat.round()}g (${macroPercentages['fat']!.round()}%)');
    buffer.writeln('• Kohlenhydrate: ${carbs.round()}g (${macroPercentages['carbs']!.round()}%)');
    
    return buffer.toString();
  }
}
