import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Dietry'**
  String get appTitle;

  /// No description provided for @overviewTitle.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get overviewTitle;

  /// No description provided for @addFoodTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintragen'**
  String get addFoodTitle;

  /// No description provided for @nutrientCalories.
  ///
  /// In de, this message translates to:
  /// **'Kalorien'**
  String get nutrientCalories;

  /// No description provided for @nutrientProtein.
  ///
  /// In de, this message translates to:
  /// **'Eiweiß'**
  String get nutrientProtein;

  /// No description provided for @nutrientFat.
  ///
  /// In de, this message translates to:
  /// **'Fett'**
  String get nutrientFat;

  /// No description provided for @nutrientCarbs.
  ///
  /// In de, this message translates to:
  /// **'Kohlenhydrate'**
  String get nutrientCarbs;

  /// No description provided for @nutrientFiber.
  ///
  /// In de, this message translates to:
  /// **'Ballaststoffe'**
  String get nutrientFiber;

  /// No description provided for @nutrientSugar.
  ///
  /// In de, this message translates to:
  /// **'Zucker'**
  String get nutrientSugar;

  /// No description provided for @nutrientSalt.
  ///
  /// In de, this message translates to:
  /// **'Salz'**
  String get nutrientSalt;

  /// No description provided for @nutrientSaturatedFat.
  ///
  /// In de, this message translates to:
  /// **'Gesättigte Fettsäuren'**
  String get nutrientSaturatedFat;

  /// No description provided for @ofWhichCarbs.
  ///
  /// In de, this message translates to:
  /// **'davon Zucker'**
  String get ofWhichCarbs;

  /// No description provided for @ofWhichFat.
  ///
  /// In de, this message translates to:
  /// **'davon gesättigt'**
  String get ofWhichFat;

  /// No description provided for @goal.
  ///
  /// In de, this message translates to:
  /// **'Ziel'**
  String get goal;

  /// No description provided for @consumed.
  ///
  /// In de, this message translates to:
  /// **'Verbraucht'**
  String get consumed;

  /// No description provided for @remaining.
  ///
  /// In de, this message translates to:
  /// **'Verbleibend'**
  String get remaining;

  /// No description provided for @today.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get today;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In de, this message translates to:
  /// **'Speichere...'**
  String get saving;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @requiredField.
  ///
  /// In de, this message translates to:
  /// **'Erforderlich'**
  String get requiredField;

  /// No description provided for @errorPrefix.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String errorPrefix(String error);

  /// No description provided for @previousDay.
  ///
  /// In de, this message translates to:
  /// **'Vorheriger Tag'**
  String get previousDay;

  /// No description provided for @nextDay.
  ///
  /// In de, this message translates to:
  /// **'Nächster Tag'**
  String get nextDay;

  /// No description provided for @loading.
  ///
  /// In de, this message translates to:
  /// **'Lade Daten...'**
  String get loading;

  /// No description provided for @navOverview.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get navOverview;

  /// No description provided for @navEntries.
  ///
  /// In de, this message translates to:
  /// **'Einträge'**
  String get navEntries;

  /// No description provided for @navActivities.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten'**
  String get navActivities;

  /// No description provided for @navReports.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get navReports;

  /// No description provided for @mealBreakfast.
  ///
  /// In de, this message translates to:
  /// **'Frühstück'**
  String get mealBreakfast;

  /// No description provided for @mealLunch.
  ///
  /// In de, this message translates to:
  /// **'Mittagessen'**
  String get mealLunch;

  /// No description provided for @mealDinner.
  ///
  /// In de, this message translates to:
  /// **'Abendessen'**
  String get mealDinner;

  /// No description provided for @mealSnack.
  ///
  /// In de, this message translates to:
  /// **'Snack'**
  String get mealSnack;

  /// No description provided for @genderMale.
  ///
  /// In de, this message translates to:
  /// **'Männlich'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In de, this message translates to:
  /// **'Weiblich'**
  String get genderFemale;

  /// No description provided for @activityLevelSedentary.
  ///
  /// In de, this message translates to:
  /// **'Wenig Bewegung (Bürojob)'**
  String get activityLevelSedentary;

  /// No description provided for @activityLevelLight.
  ///
  /// In de, this message translates to:
  /// **'Leicht aktiv (1-3x/Woche Sport)'**
  String get activityLevelLight;

  /// No description provided for @activityLevelModerate.
  ///
  /// In de, this message translates to:
  /// **'Moderat aktiv (3-5x/Woche Sport)'**
  String get activityLevelModerate;

  /// No description provided for @activityLevelActive.
  ///
  /// In de, this message translates to:
  /// **'Sehr aktiv (6-7x/Woche Sport)'**
  String get activityLevelActive;

  /// No description provided for @activityLevelVeryActive.
  ///
  /// In de, this message translates to:
  /// **'Extrem aktiv (2x täglich Training)'**
  String get activityLevelVeryActive;

  /// No description provided for @weightGoalLose.
  ///
  /// In de, this message translates to:
  /// **'Abnehmen (0.5 kg/Woche)'**
  String get weightGoalLose;

  /// No description provided for @weightGoalMaintain.
  ///
  /// In de, this message translates to:
  /// **'Gewicht halten'**
  String get weightGoalMaintain;

  /// No description provided for @weightGoalGain.
  ///
  /// In de, this message translates to:
  /// **'Zunehmen (Muskelaufbau)'**
  String get weightGoalGain;

  /// No description provided for @caloriesBurned.
  ///
  /// In de, this message translates to:
  /// **'Verbrannt'**
  String get caloriesBurned;

  /// No description provided for @netCalories.
  ///
  /// In de, this message translates to:
  /// **'Netto'**
  String get netCalories;

  /// No description provided for @date.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get date;

  /// No description provided for @noGoalTitle.
  ///
  /// In de, this message translates to:
  /// **'Kein Ernährungsziel'**
  String get noGoalTitle;

  /// No description provided for @noGoalMessage.
  ///
  /// In de, this message translates to:
  /// **'Erstelle dein erstes Ernährungsziel, um deine Fortschritte zu tracken.'**
  String get noGoalMessage;

  /// No description provided for @createGoal.
  ///
  /// In de, this message translates to:
  /// **'Ernährungsziel erstellen'**
  String get createGoal;

  /// No description provided for @entriesTitle.
  ///
  /// In de, this message translates to:
  /// **'Einträge'**
  String get entriesTitle;

  /// No description provided for @entriesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge'**
  String get entriesEmpty;

  /// No description provided for @entriesEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Füge deine erste Mahlzeit hinzu!'**
  String get entriesEmptyHint;

  /// No description provided for @deleteEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag löschen?'**
  String get deleteEntryTitle;

  /// No description provided for @deleteEntryConfirm.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du \"{name}\" wirklich löschen?'**
  String deleteEntryConfirm(String name);

  /// No description provided for @entryDeleted.
  ///
  /// In de, this message translates to:
  /// **'Eintrag gelöscht'**
  String get entryDeleted;

  /// No description provided for @myFoods.
  ///
  /// In de, this message translates to:
  /// **'Meine Lebensmittel'**
  String get myFoods;

  /// No description provided for @addEntry.
  ///
  /// In de, this message translates to:
  /// **'Eintragen'**
  String get addEntry;

  /// No description provided for @activitiesTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten'**
  String get activitiesTitle;

  /// No description provided for @activitiesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Aktivitäten'**
  String get activitiesEmpty;

  /// No description provided for @activitiesEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Füge deine erste Aktivität hinzu!'**
  String get activitiesEmptyHint;

  /// No description provided for @deleteActivityTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktivität löschen?'**
  String get deleteActivityTitle;

  /// No description provided for @deleteActivityConfirm.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du \"{name}\" wirklich löschen?'**
  String deleteActivityConfirm(String name);

  /// No description provided for @activityDeleted.
  ///
  /// In de, this message translates to:
  /// **'Aktivität gelöscht'**
  String get activityDeleted;

  /// No description provided for @addActivity.
  ///
  /// In de, this message translates to:
  /// **'Aktivität hinzufügen'**
  String get addActivity;

  /// No description provided for @myActivities.
  ///
  /// In de, this message translates to:
  /// **'Meine Aktivitäten'**
  String get myActivities;

  /// No description provided for @activityQuickAdd.
  ///
  /// In de, this message translates to:
  /// **'Aktivität schnell hinzufügen'**
  String get activityQuickAdd;

  /// No description provided for @importHealthConnect.
  ///
  /// In de, this message translates to:
  /// **'Aus Health Connect importieren'**
  String get importHealthConnect;

  /// No description provided for @healthConnectImporting.
  ///
  /// In de, this message translates to:
  /// **'Importiere Aktivitäten...'**
  String get healthConnectImporting;

  /// No description provided for @healthConnectNoResults.
  ///
  /// In de, this message translates to:
  /// **'Keine neuen Aktivitäten gefunden'**
  String get healthConnectNoResults;

  /// No description provided for @healthConnectSuccess.
  ///
  /// In de, this message translates to:
  /// **'{count} Aktivitäten importiert'**
  String healthConnectSuccess(int count);

  /// No description provided for @healthConnectError.
  ///
  /// In de, this message translates to:
  /// **'Import fehlgeschlagen: {error}'**
  String healthConnectError(String error);

  /// No description provided for @healthConnectUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Health Connect ist auf diesem Gerät nicht verfügbar'**
  String get healthConnectUnavailable;

  /// No description provided for @healthConnectSuccessBody.
  ///
  /// In de, this message translates to:
  /// **'{count} Messwerte importiert'**
  String healthConnectSuccessBody(int count);

  /// No description provided for @importRangeTitle.
  ///
  /// In de, this message translates to:
  /// **'Importzeitraum'**
  String get importRangeTitle;

  /// No description provided for @importRangeSinceGoal.
  ///
  /// In de, this message translates to:
  /// **'Ab Tracking-Start ({date})'**
  String importRangeSinceGoal(String date);

  /// No description provided for @importRangeAll.
  ///
  /// In de, this message translates to:
  /// **'Alle verfügbaren Daten'**
  String get importRangeAll;

  /// No description provided for @addFoodScreenTitle.
  ///
  /// In de, this message translates to:
  /// **'Lebensmittel eintragen'**
  String get addFoodScreenTitle;

  /// No description provided for @searchHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Apfel, Reis, Hähnchen...'**
  String get searchHint;

  /// No description provided for @onlineSearch.
  ///
  /// In de, this message translates to:
  /// **'Online-Suche'**
  String get onlineSearch;

  /// No description provided for @myDatabase.
  ///
  /// In de, this message translates to:
  /// **'Meine Datenbank'**
  String get myDatabase;

  /// No description provided for @amount.
  ///
  /// In de, this message translates to:
  /// **'Menge'**
  String get amount;

  /// No description provided for @unit.
  ///
  /// In de, this message translates to:
  /// **'Einheit'**
  String get unit;

  /// No description provided for @mealType.
  ///
  /// In de, this message translates to:
  /// **'Mahlzeit'**
  String get mealType;

  /// No description provided for @manualEntry.
  ///
  /// In de, this message translates to:
  /// **'Manuell'**
  String get manualEntry;

  /// No description provided for @useFood.
  ///
  /// In de, this message translates to:
  /// **'Verwenden'**
  String get useFood;

  /// No description provided for @saveToDatabase.
  ///
  /// In de, this message translates to:
  /// **'Zur Datenbank hinzufügen'**
  String get saveToDatabase;

  /// No description provided for @entrySaved.
  ///
  /// In de, this message translates to:
  /// **'Eintrag gespeichert!'**
  String get entrySaved;

  /// No description provided for @foodDatabaseEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine eigenen Lebensmittel'**
  String get foodDatabaseEmpty;

  /// No description provided for @searchEnterHint.
  ///
  /// In de, this message translates to:
  /// **'Enter drücken zum Suchen'**
  String get searchEnterHint;

  /// No description provided for @caloriesLabel.
  ///
  /// In de, this message translates to:
  /// **'Kalorien'**
  String get caloriesLabel;

  /// No description provided for @proteinLabel.
  ///
  /// In de, this message translates to:
  /// **'Protein'**
  String get proteinLabel;

  /// No description provided for @fatLabel.
  ///
  /// In de, this message translates to:
  /// **'Fett'**
  String get fatLabel;

  /// No description provided for @carbsLabel.
  ///
  /// In de, this message translates to:
  /// **'Kohlenhydrate'**
  String get carbsLabel;

  /// No description provided for @foodDatabaseTitle.
  ///
  /// In de, this message translates to:
  /// **'Meine Lebensmittel'**
  String get foodDatabaseTitle;

  /// No description provided for @foodAdded.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" hinzugefügt'**
  String foodAdded(String name);

  /// No description provided for @foodUpdated.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" aktualisiert'**
  String foodUpdated(String name);

  /// No description provided for @foodDeleted.
  ///
  /// In de, this message translates to:
  /// **'Gelöscht'**
  String get foodDeleted;

  /// No description provided for @deleteFoodTitle.
  ///
  /// In de, this message translates to:
  /// **'Lebensmittel löschen?'**
  String get deleteFoodTitle;

  /// No description provided for @deleteFoodConfirm.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" wird unwiderruflich gelöscht. Bestehende Einträge bleiben erhalten.'**
  String deleteFoodConfirm(String name);

  /// No description provided for @foodName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get foodName;

  /// No description provided for @foodCaloriesPer100.
  ///
  /// In de, this message translates to:
  /// **'Kalorien (kcal/100g)'**
  String get foodCaloriesPer100;

  /// No description provided for @foodProteinPer100.
  ///
  /// In de, this message translates to:
  /// **'Protein (g/100g)'**
  String get foodProteinPer100;

  /// No description provided for @foodFatPer100.
  ///
  /// In de, this message translates to:
  /// **'Fett (g/100g)'**
  String get foodFatPer100;

  /// No description provided for @foodCarbsPer100.
  ///
  /// In de, this message translates to:
  /// **'Kohlenhydrate (g/100g)'**
  String get foodCarbsPer100;

  /// No description provided for @foodCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie (optional)'**
  String get foodCategory;

  /// No description provided for @foodBrand.
  ///
  /// In de, this message translates to:
  /// **'Marke (optional)'**
  String get foodBrand;

  /// No description provided for @foodPortionsTitle.
  ///
  /// In de, this message translates to:
  /// **'Portionsgrößen'**
  String get foodPortionsTitle;

  /// No description provided for @foodPortionsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Portionen definiert – Eingabe immer in g/ml'**
  String get foodPortionsEmpty;

  /// No description provided for @foodPublic.
  ///
  /// In de, this message translates to:
  /// **'Für alle Nutzer sichtbar'**
  String get foodPublic;

  /// No description provided for @foodPublicOn.
  ///
  /// In de, this message translates to:
  /// **'Jeder kann dieses Lebensmittel finden'**
  String get foodPublicOn;

  /// No description provided for @foodPublicOff.
  ///
  /// In de, this message translates to:
  /// **'Nur du siehst diesen Eintrag'**
  String get foodPublicOff;

  /// No description provided for @foodIsLiquid.
  ///
  /// In de, this message translates to:
  /// **'Flüssigkeit'**
  String get foodIsLiquid;

  /// No description provided for @foodIsLiquidHint.
  ///
  /// In de, this message translates to:
  /// **'Menge zählt zur täglichen Wasseraufnahme'**
  String get foodIsLiquidHint;

  /// No description provided for @newFood.
  ///
  /// In de, this message translates to:
  /// **'Neues Lebensmittel'**
  String get newFood;

  /// No description provided for @nutritionPer100.
  ///
  /// In de, this message translates to:
  /// **'Nährwerte pro 100g'**
  String get nutritionPer100;

  /// No description provided for @statusPublic.
  ///
  /// In de, this message translates to:
  /// **'Öffentlich'**
  String get statusPublic;

  /// No description provided for @statusPending.
  ///
  /// In de, this message translates to:
  /// **'Ausstehend'**
  String get statusPending;

  /// No description provided for @editEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag bearbeiten'**
  String get editEntryTitle;

  /// No description provided for @entryUpdated.
  ///
  /// In de, this message translates to:
  /// **'Änderungen gespeichert!'**
  String get entryUpdated;

  /// No description provided for @profileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// No description provided for @profileDataTitle.
  ///
  /// In de, this message translates to:
  /// **'Profildaten'**
  String get profileDataTitle;

  /// No description provided for @profileDataEmpty.
  ///
  /// In de, this message translates to:
  /// **'Profil noch nicht eingerichtet'**
  String get profileDataEmpty;

  /// No description provided for @setupProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil einrichten'**
  String get setupProfile;

  /// No description provided for @editProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil bearbeiten'**
  String get editProfile;

  /// No description provided for @goalCardTitle.
  ///
  /// In de, this message translates to:
  /// **'Ernährungsziel'**
  String get goalCardTitle;

  /// No description provided for @goalEmpty.
  ///
  /// In de, this message translates to:
  /// **'Kein Ernährungsziel vorhanden'**
  String get goalEmpty;

  /// No description provided for @createGoalButton.
  ///
  /// In de, this message translates to:
  /// **'Ziel erstellen'**
  String get createGoalButton;

  /// No description provided for @adjustGoal.
  ///
  /// In de, this message translates to:
  /// **'Ziel anpassen'**
  String get adjustGoal;

  /// No description provided for @measurementTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktuelle Messung'**
  String get measurementTitle;

  /// No description provided for @measurementEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Messung vorhanden'**
  String get measurementEmpty;

  /// No description provided for @addWeight.
  ///
  /// In de, this message translates to:
  /// **'Gewicht eingeben'**
  String get addWeight;

  /// No description provided for @weight.
  ///
  /// In de, this message translates to:
  /// **'Gewicht'**
  String get weight;

  /// No description provided for @height.
  ///
  /// In de, this message translates to:
  /// **'Größe'**
  String get height;

  /// No description provided for @birthdate.
  ///
  /// In de, this message translates to:
  /// **'Geburtsdatum'**
  String get birthdate;

  /// No description provided for @ageYears.
  ///
  /// In de, this message translates to:
  /// **'{age} Jahre'**
  String ageYears(int age);

  /// No description provided for @gender.
  ///
  /// In de, this message translates to:
  /// **'Geschlecht'**
  String get gender;

  /// No description provided for @activityLevelLabel.
  ///
  /// In de, this message translates to:
  /// **'Aktivitätslevel'**
  String get activityLevelLabel;

  /// No description provided for @weightGoalLabel.
  ///
  /// In de, this message translates to:
  /// **'Gewichtsziel'**
  String get weightGoalLabel;

  /// No description provided for @bodyFat.
  ///
  /// In de, this message translates to:
  /// **'Körperfett'**
  String get bodyFat;

  /// No description provided for @muscleMass.
  ///
  /// In de, this message translates to:
  /// **'Muskelmasse'**
  String get muscleMass;

  /// No description provided for @waist.
  ///
  /// In de, this message translates to:
  /// **'Taillenumfang'**
  String get waist;

  /// No description provided for @weightProgress.
  ///
  /// In de, this message translates to:
  /// **'Gewichtsverlauf'**
  String get weightProgress;

  /// No description provided for @rangeMonth1.
  ///
  /// In de, this message translates to:
  /// **'1 Monat'**
  String get rangeMonth1;

  /// No description provided for @rangeMonths3.
  ///
  /// In de, this message translates to:
  /// **'3 Monate'**
  String get rangeMonths3;

  /// No description provided for @rangeMonths6.
  ///
  /// In de, this message translates to:
  /// **'6 Monate'**
  String get rangeMonths6;

  /// No description provided for @rangeYear1.
  ///
  /// In de, this message translates to:
  /// **'1 Jahr'**
  String get rangeYear1;

  /// No description provided for @rangeAll.
  ///
  /// In de, this message translates to:
  /// **'Alles'**
  String get rangeAll;

  /// No description provided for @deleteMeasurementTitle.
  ///
  /// In de, this message translates to:
  /// **'Messung löschen?'**
  String get deleteMeasurementTitle;

  /// No description provided for @deleteMeasurementConfirm.
  ///
  /// In de, this message translates to:
  /// **'Messung vom {date} löschen?'**
  String deleteMeasurementConfirm(String date);

  /// No description provided for @measurementDeleted.
  ///
  /// In de, this message translates to:
  /// **'Messung gelöscht'**
  String get measurementDeleted;

  /// No description provided for @profileInfoText.
  ///
  /// In de, this message translates to:
  /// **'Deine Daten werden für personalisierte Empfehlungen verwendet.'**
  String get profileInfoText;

  /// No description provided for @measurementsSection.
  ///
  /// In de, this message translates to:
  /// **'Messungen ({count})'**
  String measurementsSection(int count);

  /// No description provided for @latestBadge.
  ///
  /// In de, this message translates to:
  /// **'Aktuell'**
  String get latestBadge;

  /// No description provided for @profileSetupTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil einrichten'**
  String get profileSetupTitle;

  /// No description provided for @profileEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil bearbeiten'**
  String get profileEditTitle;

  /// No description provided for @birthdateRequired.
  ///
  /// In de, this message translates to:
  /// **'Bitte Geburtsdatum wählen'**
  String get birthdateRequired;

  /// No description provided for @heightLabel.
  ///
  /// In de, this message translates to:
  /// **'Größe *'**
  String get heightLabel;

  /// No description provided for @heightInvalid.
  ///
  /// In de, this message translates to:
  /// **'Ungültige Größe (100-250cm)'**
  String get heightInvalid;

  /// No description provided for @genderLabel.
  ///
  /// In de, this message translates to:
  /// **'Geschlecht'**
  String get genderLabel;

  /// No description provided for @activityLevelFieldLabel.
  ///
  /// In de, this message translates to:
  /// **'Aktivitätslevel'**
  String get activityLevelFieldLabel;

  /// No description provided for @weightGoalFieldLabel.
  ///
  /// In de, this message translates to:
  /// **'Gewichtsziel'**
  String get weightGoalFieldLabel;

  /// No description provided for @profileSaved.
  ///
  /// In de, this message translates to:
  /// **'Profil gespeichert!'**
  String get profileSaved;

  /// No description provided for @addMeasurementTitle.
  ///
  /// In de, this message translates to:
  /// **'Messung eingeben'**
  String get addMeasurementTitle;

  /// No description provided for @editMeasurementTitle.
  ///
  /// In de, this message translates to:
  /// **'Messung bearbeiten'**
  String get editMeasurementTitle;

  /// No description provided for @measurementDate.
  ///
  /// In de, this message translates to:
  /// **'Messdatum'**
  String get measurementDate;

  /// No description provided for @weightRequired.
  ///
  /// In de, this message translates to:
  /// **'Bitte Gewicht eingeben'**
  String get weightRequired;

  /// No description provided for @weightInvalid.
  ///
  /// In de, this message translates to:
  /// **'Ungültiges Gewicht (30-300kg)'**
  String get weightInvalid;

  /// No description provided for @bodyFatOptional.
  ///
  /// In de, this message translates to:
  /// **'Körperfett (optional)'**
  String get bodyFatOptional;

  /// No description provided for @bodyFatInvalid.
  ///
  /// In de, this message translates to:
  /// **'Ungültig (0-50%)'**
  String get bodyFatInvalid;

  /// No description provided for @muscleOptional.
  ///
  /// In de, this message translates to:
  /// **'Muskelmasse (optional)'**
  String get muscleOptional;

  /// No description provided for @waistOptional.
  ///
  /// In de, this message translates to:
  /// **'Taillenumfang (optional)'**
  String get waistOptional;

  /// No description provided for @notesOptional.
  ///
  /// In de, this message translates to:
  /// **'Notizen (optional)'**
  String get notesOptional;

  /// No description provided for @notesHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. morgens nüchtern, nach Sport...'**
  String get notesHint;

  /// No description provided for @measurementSaved.
  ///
  /// In de, this message translates to:
  /// **'Messung gespeichert!'**
  String get measurementSaved;

  /// No description provided for @advancedOptional.
  ///
  /// In de, this message translates to:
  /// **'Erweitert (optional)'**
  String get advancedOptional;

  /// No description provided for @goalRecTitle.
  ///
  /// In de, this message translates to:
  /// **'Goal-Empfehlung'**
  String get goalRecTitle;

  /// No description provided for @bodyDataTitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Körperdaten'**
  String get bodyDataTitle;

  /// No description provided for @weightLabel.
  ///
  /// In de, this message translates to:
  /// **'Gewicht'**
  String get weightLabel;

  /// No description provided for @weightInvalidRec.
  ///
  /// In de, this message translates to:
  /// **'Bitte gültiges Gewicht (30-300 kg)'**
  String get weightInvalidRec;

  /// No description provided for @heightRecLabel.
  ///
  /// In de, this message translates to:
  /// **'Größe'**
  String get heightRecLabel;

  /// No description provided for @heightRecInvalid.
  ///
  /// In de, this message translates to:
  /// **'Bitte gültige Größe (100-250 cm)'**
  String get heightRecInvalid;

  /// No description provided for @birthdateLabel.
  ///
  /// In de, this message translates to:
  /// **'Geburtsdatum'**
  String get birthdateLabel;

  /// No description provided for @birthdateSelect.
  ///
  /// In de, this message translates to:
  /// **'Datum auswählen'**
  String get birthdateSelect;

  /// No description provided for @birthdateDisplay.
  ///
  /// In de, this message translates to:
  /// **'{date}  ({age} Jahre)'**
  String birthdateDisplay(String date, int age);

  /// No description provided for @birthdateSelectSnackbar.
  ///
  /// In de, this message translates to:
  /// **'Bitte Geburtsdatum auswählen'**
  String get birthdateSelectSnackbar;

  /// No description provided for @genderRecLabel.
  ///
  /// In de, this message translates to:
  /// **'Geschlecht'**
  String get genderRecLabel;

  /// No description provided for @activitySectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Aktivität'**
  String get activitySectionTitle;

  /// No description provided for @activityRecLabel.
  ///
  /// In de, this message translates to:
  /// **'Aktivitätslevel'**
  String get activityRecLabel;

  /// No description provided for @goalSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Dein Ziel'**
  String get goalSectionTitle;

  /// No description provided for @weightGoalRecLabel.
  ///
  /// In de, this message translates to:
  /// **'Gewichtsziel'**
  String get weightGoalRecLabel;

  /// No description provided for @calculateButton.
  ///
  /// In de, this message translates to:
  /// **'Empfehlung berechnen'**
  String get calculateButton;

  /// No description provided for @calculating.
  ///
  /// In de, this message translates to:
  /// **'Berechne...'**
  String get calculating;

  /// No description provided for @recommendationTitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Empfehlung'**
  String get recommendationTitle;

  /// No description provided for @trackingMethodLabel.
  ///
  /// In de, this message translates to:
  /// **'Tracking-Methode: {method}'**
  String trackingMethodLabel(String method);

  /// No description provided for @bmrLabel.
  ///
  /// In de, this message translates to:
  /// **'Grundumsatz (BMR):'**
  String get bmrLabel;

  /// No description provided for @tdeeLabel.
  ///
  /// In de, this message translates to:
  /// **'Gesamtumsatz (TDEE):'**
  String get tdeeLabel;

  /// No description provided for @targetCalories.
  ///
  /// In de, this message translates to:
  /// **'Zielkalorien:'**
  String get targetCalories;

  /// No description provided for @macronutrients.
  ///
  /// In de, this message translates to:
  /// **'Makronährstoffe'**
  String get macronutrients;

  /// No description provided for @saveAsGoal.
  ///
  /// In de, this message translates to:
  /// **'Als Ziel speichern'**
  String get saveAsGoal;

  /// No description provided for @saveBodyData.
  ///
  /// In de, this message translates to:
  /// **'Körperdaten für Tracking speichern'**
  String get saveBodyData;

  /// No description provided for @goalSaved.
  ///
  /// In de, this message translates to:
  /// **'Goal und Körperdaten gespeichert!'**
  String get goalSaved;

  /// No description provided for @goalSavedOnly.
  ///
  /// In de, this message translates to:
  /// **'Goal gespeichert!'**
  String get goalSavedOnly;

  /// No description provided for @goalSavedDialogTitle.
  ///
  /// In de, this message translates to:
  /// **'Ziel gespeichert!'**
  String get goalSavedDialogTitle;

  /// No description provided for @goalSavedDialogContent.
  ///
  /// In de, this message translates to:
  /// **'Dein Ernährungsziel wurde erfolgreich gespeichert.'**
  String get goalSavedDialogContent;

  /// No description provided for @goalTargetLine.
  ///
  /// In de, this message translates to:
  /// **'Ziel: {calories} kcal/Tag'**
  String goalTargetLine(int calories);

  /// No description provided for @toOverview.
  ///
  /// In de, this message translates to:
  /// **'Zur Übersicht'**
  String get toOverview;

  /// No description provided for @personalizedRecTitle.
  ///
  /// In de, this message translates to:
  /// **'Personalisierte Empfehlung'**
  String get personalizedRecTitle;

  /// No description provided for @personalizedRecDesc.
  ///
  /// In de, this message translates to:
  /// **'Basierend auf deinen Körperdaten berechnen wir deinen individuellen Kalorienbedarf und Makronährstoff-Empfehlungen.'**
  String get personalizedRecDesc;

  /// No description provided for @goalExplainLose.
  ///
  /// In de, this message translates to:
  /// **'Mit einem Defizit von ca. 500 kcal/Tag kannst du etwa 0.5 kg pro Woche abnehmen.'**
  String get goalExplainLose;

  /// No description provided for @goalExplainMaintain.
  ///
  /// In de, this message translates to:
  /// **'Diese Kalorienmenge sollte dein aktuelles Gewicht halten.'**
  String get goalExplainMaintain;

  /// No description provided for @goalExplainGain.
  ///
  /// In de, this message translates to:
  /// **'Mit einem Überschuss von ca. 300 kcal/Tag kannst du gesund Muskelmasse aufbauen.'**
  String get goalExplainGain;

  /// No description provided for @trackingChooseTitle.
  ///
  /// In de, this message translates to:
  /// **'Tracking-Methode wählen'**
  String get trackingChooseTitle;

  /// No description provided for @trackingHowToTrack.
  ///
  /// In de, this message translates to:
  /// **'Wie möchtest du tracken?'**
  String get trackingHowToTrack;

  /// No description provided for @trackingDescription.
  ///
  /// In de, this message translates to:
  /// **'Wähle die Methode, die am besten zu deinem Lifestyle passt. Du kannst sie jederzeit ändern.'**
  String get trackingDescription;

  /// No description provided for @trackingRecommendedForYou.
  ///
  /// In de, this message translates to:
  /// **'Deine Empfehlung'**
  String get trackingRecommendedForYou;

  /// No description provided for @trackingWhatToTrack.
  ///
  /// In de, this message translates to:
  /// **'Was solltest du tracken?'**
  String get trackingWhatToTrack;

  /// No description provided for @trackingUseMethod.
  ///
  /// In de, this message translates to:
  /// **'Diese Methode verwenden'**
  String get trackingUseMethod;

  /// No description provided for @trackingMethodBmrOnlyName.
  ///
  /// In de, this message translates to:
  /// **'BMR + Tracking'**
  String get trackingMethodBmrOnlyName;

  /// No description provided for @trackingMethodBmrOnlyShort.
  ///
  /// In de, this message translates to:
  /// **'Alle Aktivitäten tracken'**
  String get trackingMethodBmrOnlyShort;

  /// No description provided for @trackingMethodBmrOnlyDetail.
  ///
  /// In de, this message translates to:
  /// **'Dein Kalorienziel basiert nur auf deinem Grundumsatz (BMR). Du musst ALLE körperlichen Aktivitäten tracken (Gehen, Sport, Hausarbeit). Diese Methode ist am genauesten, erfordert aber konsequentes Tracking.'**
  String get trackingMethodBmrOnlyDetail;

  /// No description provided for @trackingMethodBmrOnlyRecommended.
  ///
  /// In de, this message translates to:
  /// **'Empfohlen für:\n• Maximale Präzision\n• Du trackst gerne alles\n• Sehr variable Aktivität'**
  String get trackingMethodBmrOnlyRecommended;

  /// No description provided for @trackingMethodBmrOnlyActivityHint.
  ///
  /// In de, this message translates to:
  /// **'Activity Level wird ignoriert (immer = 1.0)'**
  String get trackingMethodBmrOnlyActivityHint;

  /// No description provided for @trackingMethodBmrOnlyTrackingGuideline.
  ///
  /// In de, this message translates to:
  /// **'✅ Tracken: ALLE Aktivitäten\n• Gehen (>10 Min)\n• Sport (Gym, Laufen, etc.)\n• Hausarbeit (Putzen, Gartenarbeit)\n• Treppen steigen (>5 Etagen)'**
  String get trackingMethodBmrOnlyTrackingGuideline;

  /// No description provided for @trackingMethodTdeeCompleteName.
  ///
  /// In de, this message translates to:
  /// **'TDEE komplett'**
  String get trackingMethodTdeeCompleteName;

  /// No description provided for @trackingMethodTdeeCompleteShort.
  ///
  /// In de, this message translates to:
  /// **'Kaum Tracking nötig'**
  String get trackingMethodTdeeCompleteShort;

  /// No description provided for @trackingMethodTdeeCompleteDetail.
  ///
  /// In de, this message translates to:
  /// **'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) inkl. deinem Aktivitätslevel. Deine täglichen Aktivitäten sind bereits eingerechnet. Du musst nur außergewöhnliche Aktivitäten tracken (z.B. 2h Wandern, Marathon). Ideal bei konstanter Routine.'**
  String get trackingMethodTdeeCompleteDetail;

  /// No description provided for @trackingMethodTdeeCompleteRecommended.
  ///
  /// In de, this message translates to:
  /// **'Empfohlen für:\n• Wenig Tracking-Aufwand\n• Konstante tägliche Routine\n• Regelmäßiger Sport (gleiche Menge)'**
  String get trackingMethodTdeeCompleteRecommended;

  /// No description provided for @trackingMethodTdeeCompleteActivityHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle dein Activity Level basierend auf GESAMTER täglicher Aktivität (inkl. Sport)'**
  String get trackingMethodTdeeCompleteActivityHint;

  /// No description provided for @trackingMethodTdeeCompleteTrackingGuideline.
  ///
  /// In de, this message translates to:
  /// **'✅ Tracken: Nur außergewöhnliche Aktivitäten\n• Marathon / Halbmarathon\n• Ganztags-Wanderung\n• Extra lange Trainingseinheiten (>2h)\n\n❌ NICHT tracken: Normale tägliche Aktivitäten\n• Reguläres Training\n• Alltags-Bewegung'**
  String get trackingMethodTdeeCompleteTrackingGuideline;

  /// No description provided for @trackingMethodTdeeHybridName.
  ///
  /// In de, this message translates to:
  /// **'TDEE + Sport-Tracking'**
  String get trackingMethodTdeeHybridName;

  /// No description provided for @trackingMethodTdeeHybridShort.
  ///
  /// In de, this message translates to:
  /// **'Nur Sport tracken'**
  String get trackingMethodTdeeHybridShort;

  /// No description provided for @trackingMethodTdeeHybridDetail.
  ///
  /// In de, this message translates to:
  /// **'Dein Kalorienziel basiert auf deinem Gesamtumsatz (TDEE) nur für den Alltag. Wähle dein Activity Level basierend auf deiner täglichen Arbeit (z.B. Bürojob = sedentary). Alle sportlichen Aktivitäten (Gym, Laufen, etc.) trackst du separat. Ideal bei variabler Sport-Routine.'**
  String get trackingMethodTdeeHybridDetail;

  /// No description provided for @trackingMethodTdeeHybridRecommended.
  ///
  /// In de, this message translates to:
  /// **'Empfohlen für:\n• Balance zwischen Genauigkeit und Aufwand\n• Variable Sport-Routine\n• Klare Trennung Alltag/Sport'**
  String get trackingMethodTdeeHybridRecommended;

  /// No description provided for @trackingMethodTdeeHybridActivityHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle dein Activity Level NUR basierend auf deiner täglichen Arbeit (ohne Sport)'**
  String get trackingMethodTdeeHybridActivityHint;

  /// No description provided for @trackingMethodTdeeHybridTrackingGuideline.
  ///
  /// In de, this message translates to:
  /// **'✅ Tracken: Alle sportlichen Aktivitäten\n• Gym / Krafttraining\n• Laufen / Joggen\n• Radfahren\n• Schwimmen\n• Sport-Kurse\n\n❌ NICHT tracken: Alltags-Bewegung\n• Arbeitsweg\n• Einkaufen\n• Normale Hausarbeit'**
  String get trackingMethodTdeeHybridTrackingGuideline;

  /// No description provided for @appSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Dein persönliches Ernährungstagebuch'**
  String get appSubtitle;

  /// No description provided for @featureTrackTitle.
  ///
  /// In de, this message translates to:
  /// **'Kalorien & Makros tracken'**
  String get featureTrackTitle;

  /// No description provided for @featureTrackSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Mahlzeiten einfach erfassen und auswerten'**
  String get featureTrackSubtitle;

  /// No description provided for @featureDatabaseTitle.
  ///
  /// In de, this message translates to:
  /// **'Große Lebensmitteldatenbank'**
  String get featureDatabaseTitle;

  /// No description provided for @featureDatabaseSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Open Food Facts, USDA und eigene Einträge'**
  String get featureDatabaseSubtitle;

  /// No description provided for @featureActivitiesTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten erfassen'**
  String get featureActivitiesTitle;

  /// No description provided for @featureActivitiesSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Sport & Bewegung in der Tagesbilanz'**
  String get featureActivitiesSubtitle;

  /// No description provided for @featureGoalsTitle.
  ///
  /// In de, this message translates to:
  /// **'Individuelle Ziele'**
  String get featureGoalsTitle;

  /// No description provided for @featureGoalsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Empfehlungen basierend auf deinen Körperdaten'**
  String get featureGoalsSubtitle;

  /// No description provided for @loginWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get loginWithGoogle;

  /// No description provided for @orContinueWith.
  ///
  /// In de, this message translates to:
  /// **'Oder fortfahren mit'**
  String get orContinueWith;

  /// No description provided for @loginWithEmail.
  ///
  /// In de, this message translates to:
  /// **'Mit E-Mail anmelden'**
  String get loginWithEmail;

  /// No description provided for @signUpWithEmail.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get signUpWithEmail;

  /// No description provided for @emailLabel.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get passwordLabel;

  /// No description provided for @nameOptionalLabel.
  ///
  /// In de, this message translates to:
  /// **'Name (optional)'**
  String get nameOptionalLabel;

  /// No description provided for @passwordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Passwort zu kurz (mind. 8 Zeichen)'**
  String get passwordTooShort;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In de, this message translates to:
  /// **'Bereits registriert? Anmelden'**
  String get alreadyHaveAccount;

  /// No description provided for @noAccount.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Konto? Registrieren'**
  String get noAccount;

  /// No description provided for @signUpSuccess.
  ///
  /// In de, this message translates to:
  /// **'Registrierung erfolgreich!'**
  String get signUpSuccess;

  /// No description provided for @privacyNote.
  ///
  /// In de, this message translates to:
  /// **'Mit der Anmeldung stimmst du unseren Datenschutzrichtlinien zu. Deine Daten werden sicher gespeichert und nicht weitergegeben.'**
  String get privacyNote;

  /// No description provided for @impressumLink.
  ///
  /// In de, this message translates to:
  /// **'Impressum & Datenschutz'**
  String get impressumLink;

  /// No description provided for @loginFailed.
  ///
  /// In de, this message translates to:
  /// **'Login fehlgeschlagen: {error}'**
  String loginFailed(String error);

  /// No description provided for @continueAsGuest.
  ///
  /// In de, this message translates to:
  /// **'Als Gast fortfahren'**
  String get continueAsGuest;

  /// No description provided for @guestModeNote.
  ///
  /// In de, this message translates to:
  /// **'Deine Daten werden nur auf diesem Gerät gespeichert. Kein Konto erforderlich!'**
  String get guestModeNote;

  /// No description provided for @guestModeError.
  ///
  /// In de, this message translates to:
  /// **'Fehler beim Aktivieren des Gastmodus'**
  String get guestModeError;

  /// No description provided for @guestModeSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden zum Synchronisieren'**
  String get guestModeSignIn;

  /// No description provided for @infoTitle.
  ///
  /// In de, this message translates to:
  /// **'Info & Impressum'**
  String get infoTitle;

  /// No description provided for @infoImpressumSection.
  ///
  /// In de, this message translates to:
  /// **'Impressum'**
  String get infoImpressumSection;

  /// No description provided for @infoPrivacySection.
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get infoPrivacySection;

  /// No description provided for @infoExternalServices.
  ///
  /// In de, this message translates to:
  /// **'Externe Dienste & Datenquellen'**
  String get infoExternalServices;

  /// No description provided for @infoOpenSource.
  ///
  /// In de, this message translates to:
  /// **'Open-Source-Bibliotheken'**
  String get infoOpenSource;

  /// No description provided for @infoDisclaimerSection.
  ///
  /// In de, this message translates to:
  /// **'Haftungsausschluss'**
  String get infoDisclaimerSection;

  /// No description provided for @infoVersion.
  ///
  /// In de, this message translates to:
  /// **'Version {version}'**
  String infoVersion(String version);

  /// No description provided for @infoDisclaimerText.
  ///
  /// In de, this message translates to:
  /// **'Die Ernährungsempfehlungen und Kalorienberechnungen in dieser App basieren auf wissenschaftlichen Formeln und dienen nur als Orientierung. Sie ersetzen keine professionelle ernährungs- oder medizinische Beratung.'**
  String get infoDisclaimerText;

  /// No description provided for @infoTmgNotice.
  ///
  /// In de, this message translates to:
  /// **'Angaben gemäß § 5 TMG'**
  String get infoTmgNotice;

  /// No description provided for @infoContact.
  ///
  /// In de, this message translates to:
  /// **'Kontakt'**
  String get infoContact;

  /// No description provided for @infoEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail: info@dietry.de'**
  String get infoEmail;

  /// No description provided for @infoResponsible.
  ///
  /// In de, this message translates to:
  /// **'Verantwortlich für den Inhalt nach § 55 Abs. 2 RStV: Thorsten Rieß (Anschrift wie oben)'**
  String get infoResponsible;

  /// No description provided for @infoDataStoredTitle.
  ///
  /// In de, this message translates to:
  /// **'Welche Daten werden gespeichert?'**
  String get infoDataStoredTitle;

  /// No description provided for @infoDataGoogleAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto-Daten (E-Mail, Name) für die Authentifizierung'**
  String get infoDataGoogleAccount;

  /// No description provided for @infoDataBody.
  ///
  /// In de, this message translates to:
  /// **'Körperdaten (Gewicht, Größe, Geburtsdatum, Geschlecht)'**
  String get infoDataBody;

  /// No description provided for @infoDataMeals.
  ///
  /// In de, this message translates to:
  /// **'Mahlzeiteneinträge und Lebensmitteldatenbank'**
  String get infoDataMeals;

  /// No description provided for @infoDataActivities.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten und Ernährungsziele'**
  String get infoDataActivities;

  /// No description provided for @infoDataStorageText.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten werden in einer gesicherten Datenbank (Neon PostgreSQL) gespeichert. Es werden keine Daten an Dritte weitergegeben. Die Authentifizierung erfolgt über Neon Auth (Google OAuth 2.0 oder E-Mail/Passwort).'**
  String get infoDataStorageText;

  /// No description provided for @infoDataDeletion.
  ///
  /// In de, this message translates to:
  /// **'Daten können jederzeit durch Löschen des Kontos entfernt werden.'**
  String get infoDataDeletion;

  /// No description provided for @infoOpenSourceText.
  ///
  /// In de, this message translates to:
  /// **'Diese App wurde mit Flutter entwickelt und nutzt folgende Pakete:'**
  String get infoOpenSourceText;

  /// No description provided for @infoOffDescription.
  ///
  /// In de, this message translates to:
  /// **'Weltweite Lebensmitteldatenbank für Nährwertinformationen. Daten stehen unter der Open Database License (ODbL).'**
  String get infoOffDescription;

  /// No description provided for @infoUsdaDescription.
  ///
  /// In de, this message translates to:
  /// **'Lebensmittelnährstoffdatenbank des US-amerikanischen Landwirtschaftsministeriums.'**
  String get infoUsdaDescription;

  /// No description provided for @infoBlsName.
  ///
  /// In de, this message translates to:
  /// **'Bundeslebensmittelschlüssel 4.0 (BLS)'**
  String get infoBlsName;

  /// No description provided for @infoBlsDescription.
  ///
  /// In de, this message translates to:
  /// **'Nationale deutsche Lebensmittelkompositionsdatenbank, herausgegeben vom Max Rubner-Institut (MRI) und dem Bundesministerium für Ernährung und Landwirtschaft.'**
  String get infoBlsDescription;

  /// No description provided for @infoBlsLicense.
  ///
  /// In de, this message translates to:
  /// **'© Max Rubner-Institut / BMEL'**
  String get infoBlsLicense;

  /// No description provided for @infoNeonName.
  ///
  /// In de, this message translates to:
  /// **'Neon (Datenbank & Authentifizierung)'**
  String get infoNeonName;

  /// No description provided for @infoNeonDescription.
  ///
  /// In de, this message translates to:
  /// **'Serverlose PostgreSQL-Datenbank und OAuth 2.0-Authentifizierungsdienst.'**
  String get infoNeonDescription;

  /// No description provided for @infoNeonLicense.
  ///
  /// In de, this message translates to:
  /// **'Proprietärer Dienst'**
  String get infoNeonLicense;

  /// No description provided for @infoGoogleDescription.
  ///
  /// In de, this message translates to:
  /// **'Optionale Authentifizierung über Google-Konto. Es werden nur E-Mail-Adresse und Name übertragen.'**
  String get infoGoogleDescription;

  /// No description provided for @infoNrvName.
  ///
  /// In de, this message translates to:
  /// **'EU-Nährstoffbezugswerte (NRV)'**
  String get infoNrvName;

  /// No description provided for @infoNrvDescription.
  ///
  /// In de, this message translates to:
  /// **'Tagesempfehlungen für Mikronährstoffe basieren auf den Nährstoffbezugswerten (NRV) gemäß Verordnung (EU) Nr. 1169/2011 des Europäischen Parlaments und des Rates.'**
  String get infoNrvDescription;

  /// No description provided for @infoNrvLicense.
  ///
  /// In de, this message translates to:
  /// **'Verordnung (EU) Nr. 1169/2011'**
  String get infoNrvLicense;

  /// No description provided for @cannotNavigateToFuture.
  ///
  /// In de, this message translates to:
  /// **'Du kannst nicht in die Zukunft blättern'**
  String get cannotNavigateToFuture;

  /// No description provided for @noGoalForDate.
  ///
  /// In de, this message translates to:
  /// **'Kein Ernährungsziel für {date} vorhanden'**
  String noGoalForDate(String date);

  /// No description provided for @infoCopyright.
  ///
  /// In de, this message translates to:
  /// **'© 2025 Thorsten Rieß · dietry.de'**
  String get infoCopyright;

  /// No description provided for @offlineMode.
  ///
  /// In de, this message translates to:
  /// **'Offline – Änderungen werden synchronisiert sobald die Verbindung steht'**
  String get offlineMode;

  /// No description provided for @pendingSyncCount.
  ///
  /// In de, this message translates to:
  /// **'Änderungen warten auf Synchronisierung'**
  String get pendingSyncCount;

  /// No description provided for @syncNow.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sync'**
  String get syncNow;

  /// No description provided for @appBarTitle.
  ///
  /// In de, this message translates to:
  /// **'Dietry'**
  String get appBarTitle;

  /// No description provided for @profileTooltip.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTooltip;

  /// No description provided for @infoTooltip.
  ///
  /// In de, this message translates to:
  /// **'Info & Impressum'**
  String get infoTooltip;

  /// No description provided for @languageTooltip.
  ///
  /// In de, this message translates to:
  /// **'Sprache wechseln'**
  String get languageTooltip;

  /// No description provided for @logoutTooltip.
  ///
  /// In de, this message translates to:
  /// **'Logout'**
  String get logoutTooltip;

  /// No description provided for @accountSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto & Daten'**
  String get accountSectionTitle;

  /// No description provided for @exportDataButton.
  ///
  /// In de, this message translates to:
  /// **'Daten exportieren'**
  String get exportDataButton;

  /// No description provided for @exportDataDescription.
  ///
  /// In de, this message translates to:
  /// **'Alle deine Einträge als CSV-Dateien herunterladen'**
  String get exportDataDescription;

  /// No description provided for @deleteAccountButton.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get deleteAccountButton;

  /// No description provided for @deleteAccountDescription.
  ///
  /// In de, this message translates to:
  /// **'Alle deine Daten unwiderruflich löschen und abmelden'**
  String get deleteAccountDescription;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto wirklich löschen?'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmText.
  ///
  /// In de, this message translates to:
  /// **'Alle deine Ernährungseinträge, Aktivitäten, Körpermaße und Ziele werden dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get deleteAccountConfirmText;

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In de, this message translates to:
  /// **'Unwiderruflich löschen'**
  String get deleteAccountConfirmButton;

  /// No description provided for @deleteAccountCredentialsHint.
  ///
  /// In de, this message translates to:
  /// **'Hinweis: Aufgrund aktueller Einschränkungen des Authentifizierungsanbieters (Neon Auth) können deine Zugangsdaten nicht automatisch zusammen mit deinen Daten gelöscht werden. Bitte wende dich an den Support, falls du auch diese entfernen möchtest.'**
  String get deleteAccountCredentialsHint;

  /// No description provided for @deleteAccountSuccess.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten wurden gelöscht.'**
  String get deleteAccountSuccess;

  /// No description provided for @exportDataSuccess.
  ///
  /// In de, this message translates to:
  /// **'Export erfolgreich'**
  String get exportDataSuccess;

  /// No description provided for @exportDataError.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen: {error}'**
  String exportDataError(String error);

  /// No description provided for @deleteAccountError.
  ///
  /// In de, this message translates to:
  /// **'Löschen fehlgeschlagen: {error}'**
  String deleteAccountError(String error);

  /// No description provided for @emailVerificationTitle.
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige deine E-Mail-Adresse!'**
  String get emailVerificationTitle;

  /// No description provided for @emailVerificationBody.
  ///
  /// In de, this message translates to:
  /// **'Wir haben einen Bestätigungslink an {email} gesendet. Klicke darauf, um dein Konto zu aktivieren, und melde dich dann an.'**
  String emailVerificationBody(String email);

  /// No description provided for @emailVerificationBack.
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Anmeldung'**
  String get emailVerificationBack;

  /// No description provided for @forgotPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get forgotPassword;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort zurücksetzen'**
  String get resetPasswordTitle;

  /// No description provided for @sendResetLink.
  ///
  /// In de, this message translates to:
  /// **'Reset-Link senden'**
  String get sendResetLink;

  /// No description provided for @resetLinkSent.
  ///
  /// In de, this message translates to:
  /// **'Link gesendet!'**
  String get resetLinkSent;

  /// No description provided for @resetLinkSentBody.
  ///
  /// In de, this message translates to:
  /// **'Wir haben einen Link zum Zurücksetzen des Passworts an {email} gesendet.'**
  String resetLinkSentBody(String email);

  /// No description provided for @waterTitle.
  ///
  /// In de, this message translates to:
  /// **'Wasseraufnahme'**
  String get waterTitle;

  /// No description provided for @waterGoalLabel.
  ///
  /// In de, this message translates to:
  /// **'Ziel: {amount} ml'**
  String waterGoalLabel(int amount);

  /// No description provided for @waterAdd.
  ///
  /// In de, this message translates to:
  /// **'Wasser hinzufügen'**
  String get waterAdd;

  /// No description provided for @waterRemove.
  ///
  /// In de, this message translates to:
  /// **'Wasser entfernen'**
  String get waterRemove;

  /// No description provided for @devBannerText.
  ///
  /// In de, this message translates to:
  /// **'⚠️ Vorab-Version · Entwicklungsdatenbank · Daten werden nicht dauerhaft gespeichert'**
  String get devBannerText;

  /// No description provided for @guestModeBannerText.
  ///
  /// In de, this message translates to:
  /// **'👤 Gastmodus · Daten werden lokal gespeichert · Melde dich an, um zu synchronisieren'**
  String get guestModeBannerText;

  /// No description provided for @waterGoalFieldLabel.
  ///
  /// In de, this message translates to:
  /// **'Wasserziel'**
  String get waterGoalFieldLabel;

  /// No description provided for @waterGoalFieldHint.
  ///
  /// In de, this message translates to:
  /// **'Empfehlung: ca. 35 ml pro kg Körpergewicht'**
  String get waterGoalFieldHint;

  /// No description provided for @waterReminderTitle.
  ///
  /// In de, this message translates to:
  /// **'Trink-Erinnerungen'**
  String get waterReminderTitle;

  /// No description provided for @waterReminderSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Alle 4 Stunden an Wasser trinken erinnern'**
  String get waterReminderSubtitle;

  /// No description provided for @waterFromFood.
  ///
  /// In de, this message translates to:
  /// **'aus Mahlzeiten'**
  String get waterFromFood;

  /// No description provided for @waterManual.
  ///
  /// In de, this message translates to:
  /// **'manuell'**
  String get waterManual;

  /// No description provided for @cheatDayTitle.
  ///
  /// In de, this message translates to:
  /// **'Cheat Day'**
  String get cheatDayTitle;

  /// No description provided for @cheatDayBanner.
  ///
  /// In de, this message translates to:
  /// **'Cheat Day! Gönn dir — wird in Berichten nicht gezählt.'**
  String get cheatDayBanner;

  /// No description provided for @markAsCheatDay.
  ///
  /// In de, this message translates to:
  /// **'Cheat Day'**
  String get markAsCheatDay;

  /// No description provided for @cheatDayMarked.
  ///
  /// In de, this message translates to:
  /// **'Cheat Day markiert ✓'**
  String get cheatDayMarked;

  /// No description provided for @cheatDayRemoved.
  ///
  /// In de, this message translates to:
  /// **'Cheat Day entfernt'**
  String get cheatDayRemoved;

  /// No description provided for @cheatDayMonthlyNudge.
  ///
  /// In de, this message translates to:
  /// **'Du hattest diesen Monat {count} Cheat Days. Alles gut, kein Stress!'**
  String cheatDayMonthlyNudge(int count);

  /// No description provided for @streakDays.
  ///
  /// In de, this message translates to:
  /// **'{count}-Tage-Streak'**
  String streakDays(int count);

  /// No description provided for @streakStart.
  ///
  /// In de, this message translates to:
  /// **'Starte heute deinen Streak!'**
  String get streakStart;

  /// No description provided for @streakBestLabel.
  ///
  /// In de, this message translates to:
  /// **'Rekord: {count}'**
  String streakBestLabel(int count);

  /// No description provided for @streakMilestoneTitle.
  ///
  /// In de, this message translates to:
  /// **'Meilenstein erreicht!'**
  String get streakMilestoneTitle;

  /// No description provided for @streakMilestoneBody.
  ///
  /// In de, this message translates to:
  /// **'Du hast einen {count}-Tage-Streak geschafft. Weiter so!'**
  String streakMilestoneBody(int count);

  /// No description provided for @serverConfigButton.
  ///
  /// In de, this message translates to:
  /// **'Serverkonfiguration'**
  String get serverConfigButton;

  /// No description provided for @serverConfigTitle.
  ///
  /// In de, this message translates to:
  /// **'Serverkonfiguration'**
  String get serverConfigTitle;

  /// No description provided for @serverConfigDescription.
  ///
  /// In de, this message translates to:
  /// **'Für selbst gehostete Installationen können Sie die App auf Ihre eigenen Neon-PostgREST- und Auth-Endpunkte verweisen. Unverändert lassen, um den Standard-Server zu verwenden.'**
  String get serverConfigDescription;

  /// No description provided for @serverConfigDataApiUrl.
  ///
  /// In de, this message translates to:
  /// **'PostgREST API-URL'**
  String get serverConfigDataApiUrl;

  /// No description provided for @serverConfigAuthBaseUrl.
  ///
  /// In de, this message translates to:
  /// **'Auth-Basis-URL'**
  String get serverConfigAuthBaseUrl;

  /// No description provided for @serverConfigCustomActive.
  ///
  /// In de, this message translates to:
  /// **'Eigener Server aktiv – es werden Ihre eigenen Endpunkte verwendet.'**
  String get serverConfigCustomActive;

  /// No description provided for @serverConfigReset.
  ///
  /// In de, this message translates to:
  /// **'Auf Standardwerte zurücksetzen'**
  String get serverConfigReset;

  /// No description provided for @feedbackTitle.
  ///
  /// In de, this message translates to:
  /// **'Feedback senden'**
  String get feedbackTitle;

  /// No description provided for @feedbackTooltip.
  ///
  /// In de, this message translates to:
  /// **'Feedback senden'**
  String get feedbackTooltip;

  /// No description provided for @feedbackEarlyAccessNote.
  ///
  /// In de, this message translates to:
  /// **'Du nutzt eine Early-Access-Version. Dein Feedback hilft uns, die App zu verbessern!'**
  String get feedbackEarlyAccessNote;

  /// No description provided for @feedbackTypeLabel.
  ///
  /// In de, this message translates to:
  /// **'Typ'**
  String get feedbackTypeLabel;

  /// No description provided for @feedbackTypeBug.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get feedbackTypeBug;

  /// No description provided for @feedbackTypeFeature.
  ///
  /// In de, this message translates to:
  /// **'Feature-Wunsch'**
  String get feedbackTypeFeature;

  /// No description provided for @feedbackTypeGeneral.
  ///
  /// In de, this message translates to:
  /// **'Allgemein'**
  String get feedbackTypeGeneral;

  /// No description provided for @feedbackRatingLabel.
  ///
  /// In de, this message translates to:
  /// **'Bewertung (optional)'**
  String get feedbackRatingLabel;

  /// No description provided for @feedbackMessageLabel.
  ///
  /// In de, this message translates to:
  /// **'Nachricht'**
  String get feedbackMessageLabel;

  /// No description provided for @feedbackMessageHint.
  ///
  /// In de, this message translates to:
  /// **'Beschreibe den Fehler, deine Idee oder deine Erfahrung…'**
  String get feedbackMessageHint;

  /// No description provided for @feedbackMessageTooShort.
  ///
  /// In de, this message translates to:
  /// **'Bitte mindestens 10 Zeichen eingeben.'**
  String get feedbackMessageTooShort;

  /// No description provided for @feedbackSubmit.
  ///
  /// In de, this message translates to:
  /// **'Absenden'**
  String get feedbackSubmit;

  /// No description provided for @feedbackThankYou.
  ///
  /// In de, this message translates to:
  /// **'Vielen Dank für dein Feedback!'**
  String get feedbackThankYou;

  /// No description provided for @reportsTitle.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get reportsTitle;

  /// No description provided for @reportsRangeWeek.
  ///
  /// In de, this message translates to:
  /// **'Woche'**
  String get reportsRangeWeek;

  /// No description provided for @reportsRangeMonth.
  ///
  /// In de, this message translates to:
  /// **'Monat'**
  String get reportsRangeMonth;

  /// No description provided for @reportsRangeYear.
  ///
  /// In de, this message translates to:
  /// **'Jahr'**
  String get reportsRangeYear;

  /// No description provided for @reportsRangeAllTime.
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get reportsRangeAllTime;

  /// No description provided for @reportsSummary.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get reportsSummary;

  /// No description provided for @reportsCalorieTrend.
  ///
  /// In de, this message translates to:
  /// **'Kalorientrend'**
  String get reportsCalorieTrend;

  /// No description provided for @reportsMacroAverage.
  ///
  /// In de, this message translates to:
  /// **'Ø Makronährstoffe'**
  String get reportsMacroAverage;

  /// No description provided for @reportsWaterIntake.
  ///
  /// In de, this message translates to:
  /// **'Wasseraufnahme'**
  String get reportsWaterIntake;

  /// No description provided for @reportsBodyWeight.
  ///
  /// In de, this message translates to:
  /// **'Körpergewicht'**
  String get reportsBodyWeight;

  /// No description provided for @reportsMostEatenFoods.
  ///
  /// In de, this message translates to:
  /// **'Top-Lebensmittel'**
  String get reportsMostEatenFoods;

  /// No description provided for @reportsSortCalories.
  ///
  /// In de, this message translates to:
  /// **'kcal'**
  String get reportsSortCalories;

  /// No description provided for @reportsSortCount.
  ///
  /// In de, this message translates to:
  /// **'Häufigkeit'**
  String get reportsSortCount;

  /// No description provided for @reportsSortWeight.
  ///
  /// In de, this message translates to:
  /// **'Gewicht'**
  String get reportsSortWeight;

  /// No description provided for @reportsNoData.
  ///
  /// In de, this message translates to:
  /// **'Keine Daten für diesen Zeitraum.'**
  String get reportsNoData;

  /// No description provided for @reportsAvgCalories.
  ///
  /// In de, this message translates to:
  /// **'Ø tägl. Kalorien'**
  String get reportsAvgCalories;

  /// No description provided for @reportsDaysTracked.
  ///
  /// In de, this message translates to:
  /// **'Tage erfasst'**
  String get reportsDaysTracked;

  /// No description provided for @reportsDaysOnTarget.
  ///
  /// In de, this message translates to:
  /// **'Tage im Ziel'**
  String get reportsDaysOnTarget;

  /// No description provided for @reportsAvgWater.
  ///
  /// In de, this message translates to:
  /// **'Ø tägl. Wasser'**
  String get reportsAvgWater;

  /// No description provided for @reportsGoalLine.
  ///
  /// In de, this message translates to:
  /// **'Ziel'**
  String get reportsGoalLine;

  /// No description provided for @reportsBodyFat.
  ///
  /// In de, this message translates to:
  /// **'Körperfett %'**
  String get reportsBodyFat;

  /// No description provided for @reportsCaloriesBurned.
  ///
  /// In de, this message translates to:
  /// **'Verbrannt'**
  String get reportsCaloriesBurned;

  /// No description provided for @reportsConsumed.
  ///
  /// In de, this message translates to:
  /// **'Aufgenommen'**
  String get reportsConsumed;

  /// No description provided for @reportsBalance.
  ///
  /// In de, this message translates to:
  /// **'Bilanz'**
  String get reportsBalance;

  /// No description provided for @reportsUpsellBasic.
  ///
  /// In de, this message translates to:
  /// **'Verfügbar in der Cloud Edition'**
  String get reportsUpsellBasic;

  /// No description provided for @reportsUpsellPro.
  ///
  /// In de, this message translates to:
  /// **'Verfügbar für Pro-Nutzer'**
  String get reportsUpsellPro;

  /// No description provided for @reportsLoading.
  ///
  /// In de, this message translates to:
  /// **'Berichte werden geladen…'**
  String get reportsLoading;

  /// No description provided for @reportsExportTooltip.
  ///
  /// In de, this message translates to:
  /// **'Als CSV exportieren'**
  String get reportsExportTooltip;

  /// No description provided for @reportsExportSuccess.
  ///
  /// In de, this message translates to:
  /// **'Export erfolgreich'**
  String get reportsExportSuccess;

  /// No description provided for @reportsExportError.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen: {error}'**
  String reportsExportError(String error);

  /// No description provided for @macroOnlyMode.
  ///
  /// In de, this message translates to:
  /// **'Nur Makros tracken (kein Kalorienziel)'**
  String get macroOnlyMode;

  /// No description provided for @caloriesTooMuch.
  ///
  /// In de, this message translates to:
  /// **'{amount} zu viel'**
  String caloriesTooMuch(String amount);

  /// No description provided for @shareProgressTitle.
  ///
  /// In de, this message translates to:
  /// **'Teile deine Fortschritte'**
  String get shareProgressTitle;

  /// No description provided for @shareTabStreak.
  ///
  /// In de, this message translates to:
  /// **'🔥 Streak'**
  String get shareTabStreak;

  /// No description provided for @shareTabDaily.
  ///
  /// In de, this message translates to:
  /// **'📊 Tägliche Ziele'**
  String get shareTabDaily;

  /// No description provided for @shareButton.
  ///
  /// In de, this message translates to:
  /// **'In sozialen Medien teilen'**
  String get shareButton;

  /// No description provided for @sharing.
  ///
  /// In de, this message translates to:
  /// **'Wird geteilt...'**
  String get sharing;

  /// No description provided for @shareHashtags.
  ///
  /// In de, this message translates to:
  /// **'#Dietry #ErnährungTracking #GesundesLeben'**
  String get shareHashtags;

  /// No description provided for @shareStreakCaption.
  ///
  /// In de, this message translates to:
  /// **'🔥 Ich bin bei {days} Tagen Streak mit Dietry!'**
  String shareStreakCaption(int days);

  /// No description provided for @streakDayText.
  ///
  /// In de, this message translates to:
  /// **'Tag'**
  String get streakDayText;

  /// No description provided for @shareStreakCaptionEnd.
  ///
  /// In de, this message translates to:
  /// **' Tage Streak!'**
  String get shareStreakCaptionEnd;

  /// No description provided for @shareDailyCaption.
  ///
  /// In de, this message translates to:
  /// **'✅ Heute meine Ernährungsziele erreicht!'**
  String get shareDailyCaption;

  /// No description provided for @shareSuccessful.
  ///
  /// In de, this message translates to:
  /// **'✅ Erfolgreich geteilt!'**
  String get shareSuccessful;

  /// No description provided for @shareFailed.
  ///
  /// In de, this message translates to:
  /// **'❌ Teilen fehlgeschlagen. Bitte versuche es erneut.'**
  String get shareFailed;

  /// No description provided for @logFood.
  ///
  /// In de, this message translates to:
  /// **'Lebensmittel eintragen'**
  String get logFood;

  /// No description provided for @nutritionInfo.
  ///
  /// In de, this message translates to:
  /// **'Nährwertinfo'**
  String get nutritionInfo;

  /// No description provided for @per100g.
  ///
  /// In de, this message translates to:
  /// **'pro 100g'**
  String get per100g;

  /// No description provided for @tags.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @addTag.
  ///
  /// In de, this message translates to:
  /// **'Tag hinzufügen'**
  String get addTag;

  /// No description provided for @tagHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. vegetarisch, vegan, roh...'**
  String get tagHint;

  /// No description provided for @filterByTag.
  ///
  /// In de, this message translates to:
  /// **'Nach Tag filtern'**
  String get filterByTag;

  /// No description provided for @deleteGuestDataTitle.
  ///
  /// In de, this message translates to:
  /// **'Gast-Daten löschen'**
  String get deleteGuestDataTitle;

  /// No description provided for @deleteGuestDataConfirm.
  ///
  /// In de, this message translates to:
  /// **'Alle deine Gast-Daten (Einträge, Ziele, Profil) werden gelöscht und können nicht wiederhergestellt werden. Fortfahren?'**
  String get deleteGuestDataConfirm;

  /// No description provided for @deleteGuestDataSuccess.
  ///
  /// In de, this message translates to:
  /// **'✅ Alle Gast-Daten gelöscht'**
  String get deleteGuestDataSuccess;

  /// No description provided for @migrationDialogTitle.
  ///
  /// In de, this message translates to:
  /// **'Gast-Daten übernehmen?'**
  String get migrationDialogTitle;

  /// No description provided for @migrationDialogContent.
  ///
  /// In de, this message translates to:
  /// **'Du hattest bereits Einträge im Gast-Modus. Diese können auf deinen Account übertragen werden.'**
  String get migrationDialogContent;

  /// No description provided for @migrationTransfer.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get migrationTransfer;

  /// No description provided for @migrationDiscard.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get migrationDiscard;

  /// No description provided for @migrationSuccess.
  ///
  /// In de, this message translates to:
  /// **'✅ {count} Einträge übertragen'**
  String migrationSuccess(int count);

  /// No description provided for @migrationError.
  ///
  /// In de, this message translates to:
  /// **'⚠️ Fehler bei der Migration (Einträge können manuell übernommen werden)'**
  String get migrationError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
