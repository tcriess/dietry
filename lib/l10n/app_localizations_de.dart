// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Dietry';

  @override
  String get overviewTitle => 'Übersicht';

  @override
  String get addFoodTitle => 'Eintragen';

  @override
  String get nutrientCalories => 'Kalorien';

  @override
  String get nutrientProtein => 'Eiweiß';

  @override
  String get nutrientFat => 'Fett';

  @override
  String get nutrientCarbs => 'Kohlenhydrate';

  @override
  String get nutrientFiber => 'Ballaststoffe';

  @override
  String get nutrientSugar => 'Zucker';

  @override
  String get nutrientSalt => 'Salz';

  @override
  String get nutrientSaturatedFat => 'Gesättigte Fettsäuren';

  @override
  String get ofWhichCarbs => 'davon Zucker';

  @override
  String get ofWhichFat => 'davon gesättigt';

  @override
  String get goal => 'Ziel';

  @override
  String get consumed => 'Verbraucht';

  @override
  String get remaining => 'Verbleibend';

  @override
  String get today => 'Heute';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get saving => 'Speichere...';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get add => 'Hinzufügen';

  @override
  String get requiredField => 'Erforderlich';

  @override
  String errorPrefix(String error) {
    return 'Fehler: $error';
  }

  @override
  String get previousDay => 'Vorheriger Tag';

  @override
  String get nextDay => 'Nächster Tag';

  @override
  String get loading => 'Lade Daten...';

  @override
  String get navOverview => 'Übersicht';

  @override
  String get navEntries => 'Einträge';

  @override
  String get navActivities => 'Aktivitäten';

  @override
  String get navReports => 'Berichte';

  @override
  String get mealBreakfast => 'Frühstück';

  @override
  String get mealLunch => 'Mittagessen';

  @override
  String get mealDinner => 'Abendessen';

  @override
  String get mealSnack => 'Snack';

  @override
  String get genderMale => 'Männlich';

  @override
  String get genderFemale => 'Weiblich';

  @override
  String get activityLevelSedentary => 'Wenig Bewegung (Bürojob)';

  @override
  String get activityLevelLight => 'Leicht aktiv (1-3x/Woche Sport)';

  @override
  String get activityLevelModerate => 'Moderat aktiv (3-5x/Woche Sport)';

  @override
  String get activityLevelActive => 'Sehr aktiv (6-7x/Woche Sport)';

  @override
  String get activityLevelVeryActive => 'Extrem aktiv (2x täglich Training)';

  @override
  String get weightGoalLose => 'Abnehmen (0.5 kg/Woche)';

  @override
  String get weightGoalMaintain => 'Gewicht halten';

  @override
  String get weightGoalGain => 'Zunehmen (Muskelaufbau)';

  @override
  String get caloriesBurned => 'Verbrannt';

  @override
  String get netCalories => 'Netto';

  @override
  String get date => 'Datum';

  @override
  String get noGoalTitle => 'Kein Ernährungsziel';

  @override
  String get noGoalMessage =>
      'Erstelle dein erstes Ernährungsziel, um deine Fortschritte zu tracken.';

  @override
  String get createGoal => 'Ernährungsziel erstellen';

  @override
  String get entriesTitle => 'Einträge';

  @override
  String get entriesEmpty => 'Noch keine Einträge';

  @override
  String get entriesEmptyHint => 'Füge deine erste Mahlzeit hinzu!';

  @override
  String get deleteEntryTitle => 'Eintrag löschen?';

  @override
  String deleteEntryConfirm(String name) {
    return 'Möchtest du \"$name\" wirklich löschen?';
  }

  @override
  String get entryDeleted => 'Eintrag gelöscht';

  @override
  String get myFoods => 'Meine Lebensmittel';

  @override
  String get addEntry => 'Eintrag hinzufügen';

  @override
  String get activitiesTitle => 'Aktivitäten';

  @override
  String get activitiesEmpty => 'Keine Aktivitäten';

  @override
  String get activitiesEmptyHint => 'Füge deine erste Aktivität hinzu!';

  @override
  String get deleteActivityTitle => 'Aktivität löschen?';

  @override
  String deleteActivityConfirm(String name) {
    return 'Möchtest du \"$name\" wirklich löschen?';
  }

  @override
  String get activityDeleted => 'Aktivität gelöscht';

  @override
  String get addActivity => 'Aktivität hinzufügen';

  @override
  String get myActivities => 'Meine Aktivitäten';

  @override
  String get importHealthConnect => 'Aus Health Connect importieren';

  @override
  String get healthConnectImporting => 'Importiere Aktivitäten...';

  @override
  String get healthConnectNoResults => 'Keine neuen Aktivitäten gefunden';

  @override
  String healthConnectSuccess(int count) {
    return '$count Aktivitäten importiert';
  }

  @override
  String healthConnectError(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get healthConnectUnavailable =>
      'Health Connect ist auf diesem Gerät nicht verfügbar';

  @override
  String healthConnectSuccessBody(int count) {
    return '$count Messwerte importiert';
  }

  @override
  String get importRangeTitle => 'Importzeitraum';

  @override
  String importRangeSinceGoal(String date) {
    return 'Ab Tracking-Start ($date)';
  }

  @override
  String get importRangeAll => 'Alle verfügbaren Daten';

  @override
  String get addFoodScreenTitle => 'Lebensmittel hinzufügen';

  @override
  String get searchHint => 'z.B. Apfel, Reis, Hähnchen...';

  @override
  String get onlineSearch => 'Online-Suche';

  @override
  String get myDatabase => 'Meine Datenbank';

  @override
  String get amount => 'Menge';

  @override
  String get unit => 'Einheit';

  @override
  String get mealType => 'Mahlzeit';

  @override
  String get manualEntry => 'Manuell';

  @override
  String get useFood => 'Verwenden';

  @override
  String get saveToDatabase => 'Zur Datenbank hinzufügen';

  @override
  String get entrySaved => 'Eintrag gespeichert!';

  @override
  String get searchEnterHint => 'Enter drücken zum Suchen';

  @override
  String get caloriesLabel => 'Kalorien';

  @override
  String get proteinLabel => 'Protein';

  @override
  String get fatLabel => 'Fett';

  @override
  String get carbsLabel => 'Kohlenhydrate';

  @override
  String get foodDatabaseTitle => 'Meine Lebensmittel';

  @override
  String foodAdded(String name) {
    return '\"$name\" hinzugefügt';
  }

  @override
  String foodUpdated(String name) {
    return '\"$name\" aktualisiert';
  }

  @override
  String get foodDeleted => 'Gelöscht';

  @override
  String get deleteFoodTitle => 'Lebensmittel löschen?';

  @override
  String deleteFoodConfirm(String name) {
    return '\"$name\" wird unwiderruflich gelöscht. Bestehende Einträge bleiben erhalten.';
  }

  @override
  String get foodName => 'Name';

  @override
  String get foodCaloriesPer100 => 'Kalorien (kcal/100g)';

  @override
  String get foodProteinPer100 => 'Protein (g/100g)';

  @override
  String get foodFatPer100 => 'Fett (g/100g)';

  @override
  String get foodCarbsPer100 => 'Kohlenhydrate (g/100g)';

  @override
  String get foodCategory => 'Kategorie (optional)';

  @override
  String get foodBrand => 'Marke (optional)';

  @override
  String get foodPortionsTitle => 'Portionsgrößen';

  @override
  String get foodPortionsEmpty =>
      'Keine Portionen definiert – Eingabe immer in g/ml';

  @override
  String get foodPublic => 'Für alle Nutzer sichtbar';

  @override
  String get foodPublicOn => 'Jeder kann dieses Lebensmittel finden';

  @override
  String get foodPublicOff => 'Nur du siehst diesen Eintrag';

  @override
  String get foodIsLiquid => 'Flüssigkeit';

  @override
  String get foodIsLiquidHint => 'Menge zählt zur täglichen Wasseraufnahme';

  @override
  String get newFood => 'Neues Lebensmittel';

  @override
  String get nutritionPer100 => 'Nährwerte pro 100g';

  @override
  String get statusPublic => 'Öffentlich';

  @override
  String get statusPending => 'Ausstehend';

  @override
  String get editEntryTitle => 'Eintrag bearbeiten';

  @override
  String get entryUpdated => 'Änderungen gespeichert!';

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileDataTitle => 'Profildaten';

  @override
  String get profileDataEmpty => 'Profil noch nicht eingerichtet';

  @override
  String get setupProfile => 'Profil einrichten';

  @override
  String get editProfile => 'Profil bearbeiten';

  @override
  String get goalCardTitle => 'Ernährungsziel';

  @override
  String get goalEmpty => 'Kein Ernährungsziel vorhanden';

  @override
  String get createGoalButton => 'Ziel erstellen';

  @override
  String get adjustGoal => 'Ziel anpassen';

  @override
  String get measurementTitle => 'Aktuelle Messung';

  @override
  String get measurementEmpty => 'Keine Messung vorhanden';

  @override
  String get addWeight => 'Gewicht eingeben';

  @override
  String get weight => 'Gewicht';

  @override
  String get height => 'Größe';

  @override
  String get birthdate => 'Geburtsdatum';

  @override
  String ageYears(int age) {
    return '$age Jahre';
  }

  @override
  String get gender => 'Geschlecht';

  @override
  String get activityLevelLabel => 'Aktivitätslevel';

  @override
  String get weightGoalLabel => 'Gewichtsziel';

  @override
  String get bodyFat => 'Körperfett';

  @override
  String get muscleMass => 'Muskelmasse';

  @override
  String get waist => 'Taillenumfang';

  @override
  String get weightProgress => 'Gewichtsverlauf';

  @override
  String get rangeMonth1 => '1 Monat';

  @override
  String get rangeMonths3 => '3 Monate';

  @override
  String get rangeMonths6 => '6 Monate';

  @override
  String get rangeYear1 => '1 Jahr';

  @override
  String get rangeAll => 'Alles';

  @override
  String get deleteMeasurementTitle => 'Messung löschen?';

  @override
  String deleteMeasurementConfirm(String date) {
    return 'Messung vom $date löschen?';
  }

  @override
  String get measurementDeleted => 'Messung gelöscht';

  @override
  String get profileInfoText =>
      'Deine Daten werden für personalisierte Empfehlungen verwendet.';

  @override
  String measurementsSection(int count) {
    return 'Messungen ($count)';
  }

  @override
  String get latestBadge => 'Aktuell';

  @override
  String get profileSetupTitle => 'Profil einrichten';

  @override
  String get profileEditTitle => 'Profil bearbeiten';

  @override
  String get birthdateRequired => 'Bitte Geburtsdatum wählen';

  @override
  String get heightLabel => 'Größe *';

  @override
  String get heightInvalid => 'Ungültige Größe (100-250cm)';

  @override
  String get genderLabel => 'Geschlecht';

  @override
  String get activityLevelFieldLabel => 'Aktivitätslevel';

  @override
  String get weightGoalFieldLabel => 'Gewichtsziel';

  @override
  String get profileSaved => 'Profil gespeichert!';

  @override
  String get addMeasurementTitle => 'Messung eingeben';

  @override
  String get editMeasurementTitle => 'Messung bearbeiten';

  @override
  String get measurementDate => 'Messdatum';

  @override
  String get weightRequired => 'Bitte Gewicht eingeben';

  @override
  String get weightInvalid => 'Ungültiges Gewicht (30-300kg)';

  @override
  String get bodyFatOptional => 'Körperfett (optional)';

  @override
  String get bodyFatInvalid => 'Ungültig (0-50%)';

  @override
  String get muscleOptional => 'Muskelmasse (optional)';

  @override
  String get waistOptional => 'Taillenumfang (optional)';

  @override
  String get notesOptional => 'Notizen (optional)';

  @override
  String get notesHint => 'z.B. morgens nüchtern, nach Sport...';

  @override
  String get measurementSaved => 'Messung gespeichert!';

  @override
  String get advancedOptional => 'Erweitert (optional)';

  @override
  String get goalRecTitle => 'Goal-Empfehlung';

  @override
  String get bodyDataTitle => 'Deine Körperdaten';

  @override
  String get weightLabel => 'Gewicht';

  @override
  String get weightInvalidRec => 'Bitte gültiges Gewicht (30-300 kg)';

  @override
  String get heightRecLabel => 'Größe';

  @override
  String get heightRecInvalid => 'Bitte gültige Größe (100-250 cm)';

  @override
  String get birthdateLabel => 'Geburtsdatum';

  @override
  String get birthdateSelect => 'Datum auswählen';

  @override
  String birthdateDisplay(String date, int age) {
    return '$date  ($age Jahre)';
  }

  @override
  String get birthdateSelectSnackbar => 'Bitte Geburtsdatum auswählen';

  @override
  String get genderRecLabel => 'Geschlecht';

  @override
  String get activitySectionTitle => 'Deine Aktivität';

  @override
  String get activityRecLabel => 'Aktivitätslevel';

  @override
  String get goalSectionTitle => 'Dein Ziel';

  @override
  String get weightGoalRecLabel => 'Gewichtsziel';

  @override
  String get calculateButton => 'Empfehlung berechnen';

  @override
  String get calculating => 'Berechne...';

  @override
  String get recommendationTitle => 'Deine Empfehlung';

  @override
  String trackingMethodLabel(String method) {
    return 'Tracking-Methode: $method';
  }

  @override
  String get bmrLabel => 'Grundumsatz (BMR):';

  @override
  String get tdeeLabel => 'Gesamtumsatz (TDEE):';

  @override
  String get targetCalories => 'Zielkalorien:';

  @override
  String get macronutrients => 'Makronährstoffe';

  @override
  String get saveAsGoal => 'Als Ziel speichern';

  @override
  String get saveBodyData => 'Körperdaten für Tracking speichern';

  @override
  String get goalSaved => 'Goal und Körperdaten gespeichert!';

  @override
  String get goalSavedOnly => 'Goal gespeichert!';

  @override
  String get goalSavedDialogTitle => 'Ziel gespeichert!';

  @override
  String get goalSavedDialogContent =>
      'Dein Ernährungsziel wurde erfolgreich gespeichert.';

  @override
  String goalTargetLine(int calories) {
    return 'Ziel: $calories kcal/Tag';
  }

  @override
  String get toOverview => 'Zur Übersicht';

  @override
  String get personalizedRecTitle => 'Personalisierte Empfehlung';

  @override
  String get personalizedRecDesc =>
      'Basierend auf deinen Körperdaten berechnen wir deinen individuellen Kalorienbedarf und Makronährstoff-Empfehlungen.';

  @override
  String get goalExplainLose =>
      'Mit einem Defizit von ca. 500 kcal/Tag kannst du etwa 0.5 kg pro Woche abnehmen.';

  @override
  String get goalExplainMaintain =>
      'Diese Kalorienmenge sollte dein aktuelles Gewicht halten.';

  @override
  String get goalExplainGain =>
      'Mit einem Überschuss von ca. 300 kcal/Tag kannst du gesund Muskelmasse aufbauen.';

  @override
  String get trackingChooseTitle => 'Tracking-Methode wählen';

  @override
  String get trackingHowToTrack => 'Wie möchtest du tracken?';

  @override
  String get trackingDescription =>
      'Wähle die Methode, die am besten zu deinem Lifestyle passt. Du kannst sie jederzeit ändern.';

  @override
  String get trackingRecommendedForYou => 'Deine Empfehlung';

  @override
  String get trackingWhatToTrack => 'Was solltest du tracken?';

  @override
  String get trackingUseMethod => 'Diese Methode verwenden';

  @override
  String get trackingMethodBmrOnlyName => 'BMR + Tracking';

  @override
  String get trackingMethodBmrOnlyShort => 'Alle Aktivitäten tracken';

  @override
  String get trackingMethodBmrOnlyDetail =>
      'Dein Kalorienziel basiert nur auf deinem Grundumsatz (BMR). Du musst ALLE körperlichen Aktivitäten tracken (Gehen, Sport, Hausarbeit). Diese Methode ist am genauesten, erfordert aber konsequentes Tracking.';

  @override
  String get trackingMethodBmrOnlyRecommended =>
      'Empfohlen für:\n• Maximale Präzision\n• Du trackst gerne alles\n• Sehr variable Aktivität';

  @override
  String get trackingMethodBmrOnlyActivityHint =>
      'Activity Level wird ignoriert (immer = 1.0)';

  @override
  String get trackingMethodBmrOnlyTrackingGuideline =>
      '✅ Tracken: ALLE Aktivitäten\n• Gehen (>10 Min)\n• Sport (Gym, Laufen, etc.)\n• Hausarbeit (Putzen, Gartenarbeit)\n• Treppen steigen (>5 Etagen)';

  @override
  String get trackingMethodTdeeCompleteName => 'TDEE komplett';

  @override
  String get trackingMethodTdeeCompleteShort => 'Kaum Tracking nötig';

  @override
  String get trackingMethodTdeeCompleteDetail =>
      'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) inkl. deinem Aktivitätslevel. Deine täglichen Aktivitäten sind bereits eingerechnet. Du musst nur außergewöhnliche Aktivitäten tracken (z.B. 2h Wandern, Marathon). Ideal bei konstanter Routine.';

  @override
  String get trackingMethodTdeeCompleteRecommended =>
      'Empfohlen für:\n• Wenig Tracking-Aufwand\n• Konstante tägliche Routine\n• Regelmäßiger Sport (gleiche Menge)';

  @override
  String get trackingMethodTdeeCompleteActivityHint =>
      'Wähle dein Activity Level basierend auf GESAMTER täglicher Aktivität (inkl. Sport)';

  @override
  String get trackingMethodTdeeCompleteTrackingGuideline =>
      '✅ Tracken: Nur außergewöhnliche Aktivitäten\n• Marathon / Halbmarathon\n• Ganztags-Wanderung\n• Extra lange Trainingseinheiten (>2h)\n\n❌ NICHT tracken: Normale tägliche Aktivitäten\n• Reguläres Training\n• Alltags-Bewegung';

  @override
  String get trackingMethodTdeeHybridName => 'TDEE + Sport-Tracking';

  @override
  String get trackingMethodTdeeHybridShort => 'Nur Sport tracken';

  @override
  String get trackingMethodTdeeHybridDetail =>
      'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) nur für den Alltag. Wähle dein Activity Level basierend auf deiner täglichen Arbeit (z.B. Bürojob = sedentary). Alle sportlichen Aktivitäten (Gym, Laufen, etc.) trackst du separat. Ideal bei variabler Sport-Routine.';

  @override
  String get trackingMethodTdeeHybridRecommended =>
      'Empfohlen für:\n• Balance zwischen Genauigkeit und Aufwand\n• Variable Sport-Routine\n• Klare Trennung Alltag/Sport';

  @override
  String get trackingMethodTdeeHybridActivityHint =>
      'Wähle dein Activity Level NUR basierend auf deiner täglichen Arbeit (ohne Sport)';

  @override
  String get trackingMethodTdeeHybridTrackingGuideline =>
      '✅ Tracken: Alle sportlichen Aktivitäten\n• Gym / Krafttraining\n• Laufen / Joggen\n• Radfahren\n• Schwimmen\n• Sport-Kurse\n\n❌ NICHT tracken: Alltags-Bewegung\n• Arbeitsweg\n• Einkaufen\n• Normale Hausarbeit';

  @override
  String get appSubtitle => 'Dein persönliches Ernährungstagebuch';

  @override
  String get featureTrackTitle => 'Kalorien & Makros tracken';

  @override
  String get featureTrackSubtitle =>
      'Mahlzeiten einfach erfassen und auswerten';

  @override
  String get featureDatabaseTitle => 'Große Lebensmitteldatenbank';

  @override
  String get featureDatabaseSubtitle =>
      'Open Food Facts, USDA und eigene Einträge';

  @override
  String get featureActivitiesTitle => 'Aktivitäten erfassen';

  @override
  String get featureActivitiesSubtitle => 'Sport & Bewegung in der Tagesbilanz';

  @override
  String get featureGoalsTitle => 'Individuelle Ziele';

  @override
  String get featureGoalsSubtitle =>
      'Empfehlungen basierend auf deinen Körperdaten';

  @override
  String get loginWithGoogle => 'Mit Google anmelden';

  @override
  String get orContinueWith => 'Oder fortfahren mit';

  @override
  String get loginWithEmail => 'Mit E-Mail anmelden';

  @override
  String get signUpWithEmail => 'Registrieren';

  @override
  String get emailLabel => 'E-Mail';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get nameOptionalLabel => 'Name (optional)';

  @override
  String get passwordTooShort => 'Passwort zu kurz (mind. 8 Zeichen)';

  @override
  String get alreadyHaveAccount => 'Bereits registriert? Anmelden';

  @override
  String get noAccount => 'Noch kein Konto? Registrieren';

  @override
  String get signUpSuccess => 'Registrierung erfolgreich!';

  @override
  String get privacyNote =>
      'Mit der Anmeldung stimmst du unseren Datenschutzrichtlinien zu. Deine Daten werden sicher gespeichert und nicht weitergegeben.';

  @override
  String get impressumLink => 'Impressum & Datenschutz';

  @override
  String loginFailed(String error) {
    return 'Login fehlgeschlagen: $error';
  }

  @override
  String get infoTitle => 'Info & Impressum';

  @override
  String get infoImpressumSection => 'Impressum';

  @override
  String get infoPrivacySection => 'Datenschutz';

  @override
  String get infoExternalServices => 'Externe Dienste & Datenquellen';

  @override
  String get infoOpenSource => 'Open-Source-Bibliotheken';

  @override
  String get infoDisclaimerSection => 'Haftungsausschluss';

  @override
  String infoVersion(String version) {
    return 'Version $version';
  }

  @override
  String get infoDisclaimerText =>
      'Die Ernährungsempfehlungen und Kalorienberechnungen in dieser App basieren auf wissenschaftlichen Formeln und dienen nur als Orientierung. Sie ersetzen keine professionelle ernährungs- oder medizinische Beratung.';

  @override
  String get infoTmgNotice => 'Angaben gemäß § 5 TMG';

  @override
  String get infoContact => 'Kontakt';

  @override
  String get infoEmail => 'E-Mail: info@dietry.de';

  @override
  String get infoResponsible =>
      'Verantwortlich für den Inhalt nach § 55 Abs. 2 RStV: Thorsten Rieß (Anschrift wie oben)';

  @override
  String get infoDataStoredTitle => 'Welche Daten werden gespeichert?';

  @override
  String get infoDataGoogleAccount =>
      'Google-Konto-Daten (E-Mail, Name) für die Authentifizierung';

  @override
  String get infoDataBody =>
      'Körperdaten (Gewicht, Größe, Geburtsdatum, Geschlecht)';

  @override
  String get infoDataMeals => 'Mahlzeiteneinträge und Lebensmitteldatenbank';

  @override
  String get infoDataActivities => 'Aktivitäten und Ernährungsziele';

  @override
  String get infoDataStorageText =>
      'Alle Daten werden in einer gesicherten Datenbank (Neon PostgreSQL) gespeichert. Es werden keine Daten an Dritte weitergegeben. Die Authentifizierung erfolgt über Google OAuth 2.0 via Neon Auth.';

  @override
  String get infoDataDeletion =>
      'Daten können jederzeit durch Löschen des Kontos entfernt werden.';

  @override
  String get infoOpenSourceText =>
      'Diese App wurde mit Flutter entwickelt und nutzt folgende Pakete:';

  @override
  String get infoOffDescription =>
      'Weltweite Lebensmitteldatenbank für Nährwertinformationen. Daten stehen unter der Open Database License (ODbL).';

  @override
  String get infoUsdaDescription =>
      'Lebensmittelnährstoffdatenbank des US-amerikanischen Landwirtschaftsministeriums.';

  @override
  String get infoNeonName => 'Neon (Datenbank & Authentifizierung)';

  @override
  String get infoNeonDescription =>
      'Serverlose PostgreSQL-Datenbank und OAuth 2.0-Authentifizierungsdienst.';

  @override
  String get infoNeonLicense => 'Proprietärer Dienst';

  @override
  String get infoGoogleDescription =>
      'Authentifizierung über Google-Konto. Es werden nur E-Mail-Adresse und Name übertragen.';

  @override
  String get cannotNavigateToFuture =>
      'Du kannst nicht in die Zukunft blättern';

  @override
  String noGoalForDate(String date) {
    return 'Kein Ernährungsziel für $date vorhanden';
  }

  @override
  String get infoCopyright => '© 2025 Simon Span · dietry.de';

  @override
  String get offlineMode =>
      'Offline – Änderungen werden synchronisiert sobald die Verbindung steht';

  @override
  String get pendingSyncCount => 'Änderungen warten auf Synchronisierung';

  @override
  String get syncNow => 'Jetzt sync';

  @override
  String get appBarTitle => 'Dietry';

  @override
  String get profileTooltip => 'Profil';

  @override
  String get infoTooltip => 'Info & Impressum';

  @override
  String get languageTooltip => 'Sprache wechseln';

  @override
  String get logoutTooltip => 'Logout';

  @override
  String get accountSectionTitle => 'Konto & Daten';

  @override
  String get exportDataButton => 'Daten exportieren';

  @override
  String get exportDataDescription =>
      'Alle deine Einträge als CSV-Dateien herunterladen';

  @override
  String get deleteAccountButton => 'Konto löschen';

  @override
  String get deleteAccountDescription =>
      'Alle deine Daten unwiderruflich löschen und abmelden';

  @override
  String get deleteAccountConfirmTitle => 'Konto wirklich löschen?';

  @override
  String get deleteAccountConfirmText =>
      'Alle deine Ernährungseinträge, Aktivitäten, Körpermaße und Ziele werden dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAccountConfirmButton => 'Unwiderruflich löschen';

  @override
  String get deleteAccountCredentialsHint =>
      'Hinweis: Aufgrund aktueller Einschränkungen des Authentifizierungsanbieters (Neon Auth) können deine Zugangsdaten nicht automatisch zusammen mit deinen Daten gelöscht werden. Bitte wende dich an den Support, falls du auch diese entfernen möchtest.';

  @override
  String get deleteAccountSuccess => 'Alle Daten wurden gelöscht.';

  @override
  String get exportDataSuccess => 'Export erfolgreich';

  @override
  String exportDataError(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String deleteAccountError(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get emailVerificationTitle => 'Bitte bestätige deine E-Mail-Adresse!';

  @override
  String emailVerificationBody(String email) {
    return 'Wir haben einen Bestätigungslink an $email gesendet. Klicke darauf, um dein Konto zu aktivieren, und melde dich dann an.';
  }

  @override
  String get emailVerificationBack => 'Zurück zur Anmeldung';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get resetPasswordTitle => 'Passwort zurücksetzen';

  @override
  String get sendResetLink => 'Reset-Link senden';

  @override
  String get resetLinkSent => 'Link gesendet!';

  @override
  String resetLinkSentBody(String email) {
    return 'Wir haben einen Link zum Zurücksetzen des Passworts an $email gesendet.';
  }

  @override
  String get waterTitle => 'Wasseraufnahme';

  @override
  String waterGoalLabel(int amount) {
    return 'Ziel: $amount ml';
  }

  @override
  String get waterAdd => 'Wasser hinzufügen';

  @override
  String get waterRemove => 'Wasser entfernen';

  @override
  String get devBannerText =>
      '⚠️ Vorab-Version · Entwicklungsdatenbank · Daten werden nicht dauerhaft gespeichert';

  @override
  String get waterGoalFieldLabel => 'Wasserziel';

  @override
  String get waterGoalFieldHint => 'Empfehlung: ca. 35 ml pro kg Körpergewicht';

  @override
  String get waterReminderTitle => 'Trink-Erinnerungen';

  @override
  String get waterReminderSubtitle =>
      'Alle 4 Stunden an Wasser trinken erinnern';

  @override
  String get waterFromFood => 'aus Mahlzeiten';

  @override
  String get waterManual => 'manuell';

  @override
  String get cheatDayTitle => 'Cheat Day';

  @override
  String get cheatDayBanner =>
      'Cheat Day! Gönn dir — wird in Berichten nicht gezählt.';

  @override
  String get markAsCheatDay => 'Cheat Day';

  @override
  String get cheatDayMarked => 'Cheat Day markiert ✓';

  @override
  String get cheatDayRemoved => 'Cheat Day entfernt';

  @override
  String cheatDayMonthlyNudge(int count) {
    return 'Du hattest diesen Monat $count Cheat Days. Alles gut, kein Stress!';
  }

  @override
  String streakDays(int count) {
    return '$count-Tage-Streak';
  }

  @override
  String get streakStart => 'Starte heute deinen Streak!';

  @override
  String streakBestLabel(int count) {
    return 'Rekord: $count';
  }

  @override
  String get streakMilestoneTitle => 'Meilenstein erreicht!';

  @override
  String streakMilestoneBody(int count) {
    return 'Du hast einen $count-Tage-Streak geschafft. Weiter so!';
  }

  @override
  String get serverConfigButton => 'Serverkonfiguration';

  @override
  String get serverConfigTitle => 'Serverkonfiguration';

  @override
  String get serverConfigDescription =>
      'Für selbst gehostete Installationen können Sie die App auf Ihre eigenen Neon-PostgREST- und Auth-Endpunkte verweisen. Unverändert lassen, um den Standard-Server zu verwenden.';

  @override
  String get serverConfigDataApiUrl => 'PostgREST API-URL';

  @override
  String get serverConfigAuthBaseUrl => 'Auth-Basis-URL';

  @override
  String get serverConfigCustomActive =>
      'Eigener Server aktiv – es werden Ihre eigenen Endpunkte verwendet.';

  @override
  String get serverConfigReset => 'Auf Standardwerte zurücksetzen';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackTooltip => 'Feedback senden';

  @override
  String get feedbackEarlyAccessNote =>
      'Du nutzt eine Early-Access-Version. Dein Feedback hilft uns, die App zu verbessern!';

  @override
  String get feedbackTypeLabel => 'Typ';

  @override
  String get feedbackTypeBug => 'Fehler';

  @override
  String get feedbackTypeFeature => 'Feature-Wunsch';

  @override
  String get feedbackTypeGeneral => 'Allgemein';

  @override
  String get feedbackRatingLabel => 'Bewertung (optional)';

  @override
  String get feedbackMessageLabel => 'Nachricht';

  @override
  String get feedbackMessageHint =>
      'Beschreibe den Fehler, deine Idee oder deine Erfahrung…';

  @override
  String get feedbackMessageTooShort => 'Bitte mindestens 10 Zeichen eingeben.';

  @override
  String get feedbackSubmit => 'Absenden';

  @override
  String get feedbackThankYou => 'Vielen Dank für dein Feedback!';

  @override
  String get reportsTitle => 'Berichte';

  @override
  String get reportsRangeWeek => 'Woche';

  @override
  String get reportsRangeMonth => 'Monat';

  @override
  String get reportsRangeYear => 'Jahr';

  @override
  String get reportsRangeAllTime => 'Gesamt';

  @override
  String get reportsSummary => 'Übersicht';

  @override
  String get reportsCalorieTrend => 'Kalorientrend';

  @override
  String get reportsMacroAverage => 'Ø Makronährstoffe';

  @override
  String get reportsWaterIntake => 'Wasseraufnahme';

  @override
  String get reportsBodyWeight => 'Körpergewicht';

  @override
  String get reportsNoData => 'Keine Daten für diesen Zeitraum.';

  @override
  String get reportsAvgCalories => 'Ø tägl. Kalorien';

  @override
  String get reportsDaysTracked => 'Tage erfasst';

  @override
  String get reportsDaysOnTarget => 'Tage im Ziel';

  @override
  String get reportsAvgWater => 'Ø tägl. Wasser';

  @override
  String get reportsGoalLine => 'Ziel';

  @override
  String get reportsBodyFat => 'Körperfett %';

  @override
  String get reportsCaloriesBurned => 'Verbrannt';

  @override
  String get reportsConsumed => 'Aufgenommen';

  @override
  String get reportsBalance => 'Bilanz';

  @override
  String get reportsUpsellBasic => 'Verfügbar in der Cloud Edition (Basic+)';

  @override
  String get reportsUpsellPro => 'Verfügbar für Pro-Nutzer';

  @override
  String get reportsLoading => 'Berichte werden geladen…';

  @override
  String get reportsExportTooltip => 'Als CSV exportieren';

  @override
  String get reportsExportSuccess => 'Export erfolgreich';

  @override
  String reportsExportError(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get macroOnlyMode => 'Nur Makros tracken (kein Kalorienziel)';

  @override
  String caloriesTooMuch(String amount) {
    return '$amount zu viel';
  }
}
