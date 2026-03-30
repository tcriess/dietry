import 'user_body_data.dart';

/// Tracking-Methode für Kalorien-Ziele
/// 
/// Bestimmt wie der Kalorienbedarf berechnet und wie Aktivitäten getrackt werden
enum TrackingMethod {
  /// BMR-basiert: Nur Grundumsatz
  /// - Ziel = BMR ± Adjustment
  /// - ALLE körperlichen Aktivitäten müssen getrackt werden
  /// - Genaueste Methode, erfordert konsequentes Tracking
  /// - Empfohlen für: Detailliertes Tracking, präzise Kontrolle
  bmrOnly,

  /// TDEE-basiert: Gesamtumsatz mit Activity Level
  /// - Ziel = TDEE ± Adjustment (TDEE = BMR × Activity Multiplier)
  /// - Aktivitäten sind bereits eingerechnet
  /// - Nur außergewöhnliche Aktivitäten tracken (z.B. Marathon)
  /// - Empfohlen für: Konstante Routine, wenig Tracking-Aufwand
  tdeeComplete,

  /// Hybrid: Gesamtumsatz für Alltag + Sport-Tracking
  /// - Ziel = TDEE (nur Alltag) ± Adjustment
  /// - Activity Level = sedentary/light (nur tägliche Arbeit)
  /// - Alle sportlichen Aktivitäten tracken
  /// - Empfohlen für: Variable Sport-Routine, flexibles Tracking
  tdeeHybrid,
}

extension TrackingMethodExtension on TrackingMethod {
  String get displayName {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return 'BMR + Tracking';
      case TrackingMethod.tdeeComplete:
        return 'TDEE komplett';
      case TrackingMethod.tdeeHybrid:
        return 'TDEE + Sport-Tracking';
    }
  }

  String get shortDescription {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return 'Alle Aktivitäten tracken';
      case TrackingMethod.tdeeComplete:
        return 'Kaum Tracking nötig';
      case TrackingMethod.tdeeHybrid:
        return 'Nur Sport tracken';
    }
  }

  String get detailedDescription {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return 'Dein Kalorienziel basiert nur auf deinem Grundumsatz (BMR). '
            'Du musst ALLE körperlichen Aktivitäten tracken (Gehen, Sport, Hausarbeit). '
            'Diese Methode ist am genauesten, erfordert aber konsequentes Tracking.';
      case TrackingMethod.tdeeComplete:
        return 'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) inkl. deinem Aktivitätslevel. '
            'Deine täglichen Aktivitäten sind bereits eingerechnet. '
            'Du musst nur außergewöhnliche Aktivitäten tracken (z.B. 2h Wandern, Marathon). '
            'Ideal bei konstanter Routine.';
      case TrackingMethod.tdeeHybrid:
        return 'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) nur für den Alltag. '
            'Wähle dein Activity Level basierend auf deiner täglichen Arbeit (z.B. Bürojob = sedentary). '
            'Alle sportlichen Aktivitäten (Gym, Laufen, etc.) trackst du separat. '
            'Ideal bei variabler Sport-Routine.';
    }
  }

  String get recommendedFor {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return 'Empfohlen für:\n'
            '• Maximale Präzision\n'
            '• Du trackst gerne alles\n'
            '• Sehr variable Aktivität';
      case TrackingMethod.tdeeComplete:
        return 'Empfohlen für:\n'
            '• Wenig Tracking-Aufwand\n'
            '• Konstante tägliche Routine\n'
            '• Regelmäßiger Sport (gleiche Menge)';
      case TrackingMethod.tdeeHybrid:
        return 'Empfohlen für:\n'
            '• Balance zwischen Genauigkeit und Aufwand\n'
            '• Variable Sport-Routine\n'
            '• Klare Trennung Alltag/Sport';
    }
  }

  String get activityLevelHint {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return 'Activity Level wird ignoriert (immer = 1.0)';
      case TrackingMethod.tdeeComplete:
        return 'Wähle dein Activity Level basierend auf GESAMTER täglicher Aktivität (inkl. Sport)';
      case TrackingMethod.tdeeHybrid:
        return 'Wähle dein Activity Level NUR basierend auf deiner täglichen Arbeit (ohne Sport)';
    }
  }

  /// Gibt an, welche Aktivitäten getrackt werden sollten
  String get trackingGuideline {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return '✅ Tracken: ALLE Aktivitäten\n'
            '• Gehen (>10 Min)\n'
            '• Sport (Gym, Laufen, etc.)\n'
            '• Hausarbeit (Putzen, Gartenarbeit)\n'
            '• Treppen steigen (>5 Etagen)';
      case TrackingMethod.tdeeComplete:
        return '✅ Tracken: Nur außergewöhnliche Aktivitäten\n'
            '• Marathon / Halbmarathon\n'
            '• Ganztags-Wanderung\n'
            '• Extra lange Trainingseinheiten (>2h)\n'
            '\n'
            '❌ NICHT tracken: Normale tägliche Aktivitäten\n'
            '• Reguläres Training\n'
            '• Alltags-Bewegung';
      case TrackingMethod.tdeeHybrid:
        return '✅ Tracken: Alle sportlichen Aktivitäten\n'
            '• Gym / Krafttraining\n'
            '• Laufen / Joggen\n'
            '• Radfahren\n'
            '• Schwimmen\n'
            '• Sport-Kurse\n'
            '\n'
            '❌ NICHT tracken: Alltags-Bewegung\n'
            '• Arbeitsweg\n'
            '• Einkaufen\n'
            '• Normale Hausarbeit';
    }
  }

  /// Gibt an, ob Activity Level verwendet wird
  bool get usesActivityLevel {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return false; // Immer 1.0
      case TrackingMethod.tdeeComplete:
      case TrackingMethod.tdeeHybrid:
        return true;
    }
  }

  /// Gibt das empfohlene Activity Level für diese Methode zurück
  /// (Nur für hybrid relevant)
  ActivityLevel get recommendedActivityLevel {
    switch (this) {
      case TrackingMethod.bmrOnly:
        return ActivityLevel.sedentary; // Wird ignoriert
      case TrackingMethod.tdeeComplete:
        return ActivityLevel.moderate; // Muss vom User gewählt werden
      case TrackingMethod.tdeeHybrid:
        return ActivityLevel.sedentary; // Nur Alltag, kein Sport
    }
  }
}

