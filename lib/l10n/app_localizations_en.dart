// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dietry';

  @override
  String get overviewTitle => 'Overview';

  @override
  String get addFoodTitle => 'Add Food';

  @override
  String get nutrientCalories => 'Calories';

  @override
  String get nutrientProtein => 'Protein';

  @override
  String get nutrientFat => 'Fat';

  @override
  String get nutrientCarbs => 'Carbohydrates';

  @override
  String get nutrientFiber => 'Fiber';

  @override
  String get nutrientSugar => 'Sugar';

  @override
  String get nutrientSalt => 'Salt';

  @override
  String get nutrientSaturatedFat => 'Saturated Fat';

  @override
  String get ofWhichCarbs => 'of which sugar';

  @override
  String get ofWhichFat => 'of which saturated';

  @override
  String get goal => 'Goal';

  @override
  String get consumed => 'Consumed';

  @override
  String get remaining => 'Remaining';

  @override
  String get today => 'Today';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving...';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get requiredField => 'Required';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get previousDay => 'Previous Day';

  @override
  String get nextDay => 'Next Day';

  @override
  String get loading => 'Loading...';

  @override
  String get navOverview => 'Overview';

  @override
  String get navEntries => 'Entries';

  @override
  String get navActivities => 'Activities';

  @override
  String get navReports => 'Reports';

  @override
  String get mealBreakfast => 'Breakfast';

  @override
  String get mealLunch => 'Lunch';

  @override
  String get mealDinner => 'Dinner';

  @override
  String get mealSnack => 'Snack';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get activityLevelSedentary => 'Sedentary (Office job)';

  @override
  String get activityLevelLight => 'Light (1-3x/week exercise)';

  @override
  String get activityLevelModerate => 'Moderate (3-5x/week exercise)';

  @override
  String get activityLevelActive => 'Active (6-7x/week exercise)';

  @override
  String get activityLevelVeryActive => 'Very active (2x daily training)';

  @override
  String get weightGoalLose => 'Lose Weight (0.5 kg/week)';

  @override
  String get weightGoalMaintain => 'Maintain Weight';

  @override
  String get weightGoalGain => 'Gain Weight (Build Muscle)';

  @override
  String get caloriesBurned => 'Burned';

  @override
  String get netCalories => 'Net';

  @override
  String get date => 'Date';

  @override
  String get noGoalTitle => 'No Nutrition Goal';

  @override
  String get noGoalMessage =>
      'Create your first nutrition goal to track your progress.';

  @override
  String get createGoal => 'Create Nutrition Goal';

  @override
  String get entriesTitle => 'Entries';

  @override
  String get entriesEmpty => 'No entries yet';

  @override
  String get entriesEmptyHint => 'Add your first meal!';

  @override
  String get deleteEntryTitle => 'Delete Entry?';

  @override
  String deleteEntryConfirm(String name) {
    return 'Do you really want to delete \"$name\"?';
  }

  @override
  String get entryDeleted => 'Entry deleted';

  @override
  String get myFoods => 'My Foods';

  @override
  String get addEntry => 'Log Food';

  @override
  String get mealTemplates => 'Meal Templates';

  @override
  String get activitiesTitle => 'Activities';

  @override
  String get activitiesEmpty => 'No Activities';

  @override
  String get activitiesEmptyHint => 'Add your first activity!';

  @override
  String get deleteActivityTitle => 'Delete Activity?';

  @override
  String deleteActivityConfirm(String name) {
    return 'Do you really want to delete \"$name\"?';
  }

  @override
  String get activityDeleted => 'Activity deleted';

  @override
  String get addActivity => 'Add Activity';

  @override
  String get myActivities => 'My Activities';

  @override
  String get activityQuickAdd => 'Quick Add Activity';

  @override
  String get importHealthConnect => 'Import from Health Connect';

  @override
  String get healthConnectImporting => 'Importing activities...';

  @override
  String get healthConnectNoResults => 'No new activities found';

  @override
  String healthConnectSuccess(int count) {
    return '$count activities imported';
  }

  @override
  String healthConnectError(String error) {
    return 'Import failed: $error';
  }

  @override
  String get healthConnectUnavailable =>
      'Health Connect not available on this device';

  @override
  String healthConnectSuccessBody(int count) {
    return '$count measurements imported';
  }

  @override
  String get importRangeTitle => 'Import range';

  @override
  String importRangeSinceGoal(String date) {
    return 'Since tracking start ($date)';
  }

  @override
  String get importRangeAll => 'All available data';

  @override
  String get addFoodScreenTitle => 'Log Food';

  @override
  String get searchHint => 'e.g., Apple, Rice, Chicken...';

  @override
  String get onlineSearch => 'Online Search';

  @override
  String get myDatabase => 'My Database';

  @override
  String get amount => 'Amount';

  @override
  String get unit => 'Unit';

  @override
  String get mealType => 'Meal';

  @override
  String get manualEntry => 'Manual';

  @override
  String get useFood => 'Use';

  @override
  String get saveToDatabase => 'Add to Database';

  @override
  String get entrySaved => 'Entry saved!';

  @override
  String get foodDatabaseEmpty => 'No custom foods yet';

  @override
  String get searchEnterHint => 'Press Enter to search';

  @override
  String get caloriesLabel => 'Calories';

  @override
  String get proteinLabel => 'Protein';

  @override
  String get fatLabel => 'Fat';

  @override
  String get carbsLabel => 'Carbohydrates';

  @override
  String get foodDatabaseTitle => 'My Foods';

  @override
  String foodAdded(String name) {
    return '\"$name\" added';
  }

  @override
  String foodUpdated(String name) {
    return '\"$name\" updated';
  }

  @override
  String get foodDeleted => 'Deleted';

  @override
  String get deleteFoodTitle => 'Delete Food?';

  @override
  String deleteFoodConfirm(String name) {
    return '\"$name\" will be permanently deleted. Existing entries are preserved.';
  }

  @override
  String get foodName => 'Name';

  @override
  String get foodCaloriesPer100 => 'Calories (kcal/100g)';

  @override
  String get foodProteinPer100 => 'Protein (g/100g)';

  @override
  String get foodFatPer100 => 'Fat (g/100g)';

  @override
  String get foodCarbsPer100 => 'Carbohydrates (g/100g)';

  @override
  String get foodCategory => 'Category (optional)';

  @override
  String get foodBrand => 'Brand (optional)';

  @override
  String get foodPortionsTitle => 'Portion Sizes';

  @override
  String get foodPortionsEmpty => 'No portions defined – always enter in g/ml';

  @override
  String get foodPublic => 'Visible to all users';

  @override
  String get foodPublicOn => 'Everyone can find this food';

  @override
  String get foodPublicOff => 'Only you see this entry';

  @override
  String get foodIsLiquid => 'Liquid food';

  @override
  String get foodIsLiquidHint => 'Amount counted toward daily water intake';

  @override
  String get newFood => 'New Food';

  @override
  String get nutritionPer100 => 'Nutrition per 100g';

  @override
  String get statusPublic => 'Public';

  @override
  String get statusPending => 'Pending';

  @override
  String get editEntryTitle => 'Edit Entry';

  @override
  String get entryUpdated => 'Changes saved!';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileDataTitle => 'Profile Data';

  @override
  String get profileDataEmpty => 'Profile not set up yet';

  @override
  String get setupProfile => 'Set Up Profile';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get goalCardTitle => 'Nutrition Goal';

  @override
  String get goalEmpty => 'No nutrition goal set';

  @override
  String get createGoalButton => 'Create Goal';

  @override
  String get adjustGoal => 'Adjust Goal';

  @override
  String get measurementTitle => 'Current Measurement';

  @override
  String get measurementEmpty => 'No measurement recorded';

  @override
  String get addWeight => 'Enter Weight';

  @override
  String get weight => 'Weight';

  @override
  String get height => 'Height';

  @override
  String get birthdate => 'Date of Birth';

  @override
  String ageYears(int age) {
    return '$age years';
  }

  @override
  String get gender => 'Gender';

  @override
  String get activityLevelLabel => 'Activity Level';

  @override
  String get weightGoalLabel => 'Weight Goal';

  @override
  String get bodyFat => 'Body Fat';

  @override
  String get muscleMass => 'Muscle Mass';

  @override
  String get waist => 'Waist Circumference';

  @override
  String get weightProgress => 'Weight Progress';

  @override
  String get rangeMonth1 => '1 Month';

  @override
  String get rangeMonths3 => '3 Months';

  @override
  String get rangeMonths6 => '6 Months';

  @override
  String get rangeYear1 => '1 Year';

  @override
  String get rangeAll => 'All';

  @override
  String get deleteMeasurementTitle => 'Delete Measurement?';

  @override
  String deleteMeasurementConfirm(String date) {
    return 'Delete measurement from $date?';
  }

  @override
  String get measurementDeleted => 'Measurement deleted';

  @override
  String get profileInfoText =>
      'Your data is used for personalized recommendations.';

  @override
  String measurementsSection(int count) {
    return 'Measurements ($count)';
  }

  @override
  String get latestBadge => 'Latest';

  @override
  String get profileSetupTitle => 'Set Up Profile';

  @override
  String get profileEditTitle => 'Edit Profile';

  @override
  String get birthdateRequired => 'Please select date of birth';

  @override
  String get heightLabel => 'Height *';

  @override
  String get heightInvalid => 'Invalid height (100-250cm)';

  @override
  String get genderLabel => 'Gender';

  @override
  String get activityLevelFieldLabel => 'Activity Level';

  @override
  String get weightGoalFieldLabel => 'Weight Goal';

  @override
  String get profileSaved => 'Profile saved!';

  @override
  String get addMeasurementTitle => 'Enter Measurement';

  @override
  String get editMeasurementTitle => 'Edit Measurement';

  @override
  String get measurementDate => 'Measurement Date';

  @override
  String get weightRequired => 'Please enter weight';

  @override
  String get weightInvalid => 'Invalid weight (30-300kg)';

  @override
  String get bodyFatOptional => 'Body Fat (optional)';

  @override
  String get bodyFatInvalid => 'Invalid (0-50%)';

  @override
  String get muscleOptional => 'Muscle Mass (optional)';

  @override
  String get waistOptional => 'Waist Circumference (optional)';

  @override
  String get notesOptional => 'Notes (optional)';

  @override
  String get notesHint => 'e.g., morning fasting, after exercise...';

  @override
  String get measurementSaved => 'Measurement saved!';

  @override
  String get advancedOptional => 'Advanced (optional)';

  @override
  String get goalRecTitle => 'Goal Recommendation';

  @override
  String get bodyDataTitle => 'Your Body Data';

  @override
  String get weightLabel => 'Weight';

  @override
  String get weightInvalidRec => 'Please enter valid weight (30-300 kg)';

  @override
  String get heightRecLabel => 'Height';

  @override
  String get heightRecInvalid => 'Please enter valid height (100-250 cm)';

  @override
  String get birthdateLabel => 'Date of Birth';

  @override
  String get birthdateSelect => 'Select date';

  @override
  String birthdateDisplay(String date, int age) {
    return '$date  ($age years)';
  }

  @override
  String get birthdateSelectSnackbar => 'Please select date of birth';

  @override
  String get genderRecLabel => 'Gender';

  @override
  String get activitySectionTitle => 'Your Activity';

  @override
  String get activityRecLabel => 'Activity Level';

  @override
  String get goalSectionTitle => 'Your Goal';

  @override
  String get weightGoalRecLabel => 'Weight Goal';

  @override
  String get calculateButton => 'Calculate Recommendation';

  @override
  String get calculating => 'Calculating...';

  @override
  String get recommendationTitle => 'Your Recommendation';

  @override
  String trackingMethodLabel(String method) {
    return 'Tracking Method: $method';
  }

  @override
  String get bmrLabel => 'Basal Metabolic Rate (BMR):';

  @override
  String get tdeeLabel => 'Total Daily Energy Expenditure (TDEE):';

  @override
  String get targetCalories => 'Target Calories:';

  @override
  String get macronutrients => 'Macronutrients';

  @override
  String get saveAsGoal => 'Save as Goal';

  @override
  String get saveBodyData => 'Save body data for tracking';

  @override
  String get goalSaved => 'Goal and body data saved!';

  @override
  String get goalSavedOnly => 'Goal saved!';

  @override
  String get goalSavedDialogTitle => 'Goal Saved!';

  @override
  String get goalSavedDialogContent =>
      'Your nutrition goal has been saved successfully.';

  @override
  String goalTargetLine(int calories) {
    return 'Goal: $calories kcal/day';
  }

  @override
  String get toOverview => 'To Overview';

  @override
  String get personalizedRecTitle => 'Personalized Recommendation';

  @override
  String get personalizedRecDesc =>
      'Based on your body data we calculate your individual calorie needs and macronutrient recommendations.';

  @override
  String get goalExplainLose =>
      'With a deficit of ~500 kcal/day you can lose about 0.5 kg per week.';

  @override
  String get goalExplainMaintain =>
      'This calorie amount should maintain your current weight.';

  @override
  String get goalExplainGain =>
      'With a surplus of ~300 kcal/day you can build muscle mass healthily.';

  @override
  String get trackingChooseTitle => 'Choose Tracking Method';

  @override
  String get trackingHowToTrack => 'How do you want to track?';

  @override
  String get trackingDescription =>
      'Choose the method that best fits your lifestyle. You can change it anytime.';

  @override
  String get trackingRecommendedForYou => 'Your Recommendation';

  @override
  String get trackingWhatToTrack => 'What should you track?';

  @override
  String get trackingUseMethod => 'Use This Method';

  @override
  String get trackingMethodBmrOnlyName => 'BMR + Tracking';

  @override
  String get trackingMethodBmrOnlyShort => 'Track all activities';

  @override
  String get trackingMethodBmrOnlyDetail =>
      'Your calorie goal is based solely on your Basal Metabolic Rate (BMR). You must track ALL physical activities (walking, exercise, housework). This method is the most accurate but requires consistent tracking.';

  @override
  String get trackingMethodBmrOnlyRecommended =>
      'Recommended for:\n• Maximum precision\n• You enjoy tracking everything\n• Highly variable activity levels';

  @override
  String get trackingMethodBmrOnlyActivityHint =>
      'Activity Level is ignored (always = 1.0)';

  @override
  String get trackingMethodBmrOnlyTrackingGuideline =>
      '✅ Track: ALL activities\n• Walking (>10 min)\n• Exercise (gym, running, etc.)\n• Housework (cleaning, gardening)\n• Climbing stairs (>5 flights)';

  @override
  String get trackingMethodTdeeCompleteName => 'TDEE Complete';

  @override
  String get trackingMethodTdeeCompleteShort => 'Minimal tracking needed';

  @override
  String get trackingMethodTdeeCompleteDetail =>
      'Your calorie goal is based on your Total Daily Energy Expenditure (TDEE) including your activity level. Your daily activities are already accounted for. You only need to track exceptional activities (e.g., 2-hour hike, marathon). Ideal for consistent routines.';

  @override
  String get trackingMethodTdeeCompleteRecommended =>
      'Recommended for:\n• Minimal tracking effort\n• Consistent daily routine\n• Regular exercise (same amount)';

  @override
  String get trackingMethodTdeeCompleteActivityHint =>
      'Choose your Activity Level based on TOTAL daily activity (including exercise)';

  @override
  String get trackingMethodTdeeCompleteTrackingGuideline =>
      '✅ Track: Only exceptional activities\n• Marathon / Half-marathon\n• All-day hiking trip\n• Extra long training sessions (>2h)\n\n❌ DO NOT track: Normal daily activities\n• Regular training\n• Daily movement';

  @override
  String get trackingMethodTdeeHybridName => 'TDEE + Sport Tracking';

  @override
  String get trackingMethodTdeeHybridShort => 'Track sports only';

  @override
  String get trackingMethodTdeeHybridDetail =>
      'Your calorie goal is based on your Total Daily Energy Expenditure (TDEE) for daily life only. Choose your Activity Level based on your daily work (e.g., desk job = sedentary). Track all exercise activities (gym, running, etc.) separately. Ideal for variable exercise routines.';

  @override
  String get trackingMethodTdeeHybridRecommended =>
      'Recommended for:\n• Balance between accuracy and effort\n• Variable exercise routine\n• Clear separation of daily vs. exercise';

  @override
  String get trackingMethodTdeeHybridActivityHint =>
      'Choose your Activity Level ONLY based on your daily work (without exercise)';

  @override
  String get trackingMethodTdeeHybridTrackingGuideline =>
      '✅ Track: All exercise activities\n• Gym / Strength training\n• Running / Jogging\n• Cycling\n• Swimming\n• Sports classes\n\n❌ DO NOT track: Daily movement\n• Commute\n• Shopping\n• Normal housework';

  @override
  String get appSubtitle => 'Your personal nutrition diary';

  @override
  String get featureTrackTitle => 'Track Calories & Macros';

  @override
  String get featureTrackSubtitle => 'Easily record and analyze meals';

  @override
  String get featureDatabaseTitle => 'Large Food Database';

  @override
  String get featureDatabaseSubtitle =>
      'Open Food Facts, USDA and custom entries';

  @override
  String get featureActivitiesTitle => 'Track Activities';

  @override
  String get featureActivitiesSubtitle => 'Sport & exercise in daily balance';

  @override
  String get featureGoalsTitle => 'Individual Goals';

  @override
  String get featureGoalsSubtitle => 'Recommendations based on your body data';

  @override
  String get loginWithGoogle => 'Sign in with Google';

  @override
  String get orContinueWith => 'Or continue with';

  @override
  String get loginWithEmail => 'Sign in with email';

  @override
  String get signUpWithEmail => 'Sign up';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get nameOptionalLabel => 'Name (optional)';

  @override
  String get passwordTooShort => 'Password too short (min. 8 characters)';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get noAccount => 'No account yet? Sign up';

  @override
  String get signUpSuccess => 'Registration successful!';

  @override
  String get privacyNote =>
      'By signing in you agree to our privacy policy. Your data is stored securely and not shared.';

  @override
  String get impressumLink => 'Legal Notice & Privacy';

  @override
  String loginFailed(String error) {
    return 'Login failed: $error';
  }

  @override
  String get continueAsGuest => 'Continue as Guest';

  @override
  String get guestModeNote =>
      'Your data is stored locally on this device only. No account needed!';

  @override
  String get guestModeError => 'Error enabling guest mode';

  @override
  String get guestModeSignIn => 'Sign in to sync';

  @override
  String get infoTitle => 'Info & Legal Notice';

  @override
  String get infoImpressumSection => 'Legal Notice';

  @override
  String get infoPrivacySection => 'Privacy';

  @override
  String get infoExternalServices => 'External Services & Data Sources';

  @override
  String get infoOpenSource => 'Open Source Libraries';

  @override
  String get infoDisclaimerSection => 'Disclaimer';

  @override
  String infoVersion(String version) {
    return 'Version $version';
  }

  @override
  String get infoDisclaimerText =>
      'The nutritional recommendations and calorie calculations in this app are based on scientific formulas and serve only as guidance. They do not replace professional nutritional or medical advice.';

  @override
  String get infoTmgNotice => 'Information according to § 5 TMG';

  @override
  String get infoContact => 'Contact';

  @override
  String get infoEmail => 'Email: info@dietry.de';

  @override
  String get infoResponsible =>
      'Responsible for content according to § 55 para. 2 RStV: Thorsten Rieß (address as above)';

  @override
  String get infoDataStoredTitle => 'What data is stored?';

  @override
  String get infoDataGoogleAccount =>
      'Account data (email, name) for authentication';

  @override
  String get infoDataBody =>
      'Body data (weight, height, date of birth, gender)';

  @override
  String get infoDataMeals => 'Meal entries and food database';

  @override
  String get infoDataActivities => 'Activities and nutrition goals';

  @override
  String get infoDataStorageText =>
      'All data is stored in a secure database (Neon PostgreSQL). No data is shared with third parties. Authentication is handled via Neon Auth (Google OAuth 2.0 or email/password).';

  @override
  String get infoDataDeletion =>
      'Data can be removed at any time by deleting the account.';

  @override
  String get infoOpenSourceText =>
      'This app was built with Flutter and uses the following packages:';

  @override
  String get infoOffDescription =>
      'Worldwide food database for nutritional information. Data is available under the Open Database License (ODbL).';

  @override
  String get infoUsdaDescription =>
      'Food nutrient database from the U.S. Department of Agriculture.';

  @override
  String get infoBlsName => 'Bundeslebensmittelschlüssel 4.0 (BLS)';

  @override
  String get infoBlsDescription =>
      'German national food composition database published by the Max Rubner-Institut (MRI) and the German Federal Ministry of Food and Agriculture.';

  @override
  String get infoBlsLicense => '© Max Rubner-Institut / BMEL';

  @override
  String get infoNeonName => 'Neon (Database & Authentication)';

  @override
  String get infoNeonDescription =>
      'Serverless PostgreSQL database and OAuth 2.0 authentication service.';

  @override
  String get infoNeonLicense => 'Proprietary service';

  @override
  String get infoGoogleDescription =>
      'Optional authentication via Google account. Only email address and name are transmitted.';

  @override
  String get infoNrvName => 'EU Nutrient Reference Values (NRV)';

  @override
  String get infoNrvDescription =>
      'Daily micronutrient recommendations are based on Nutrient Reference Values (NRV) per Regulation (EU) No 1169/2011 of the European Parliament and of the Council.';

  @override
  String get infoNrvLicense => 'Regulation (EU) No 1169/2011';

  @override
  String get cannotNavigateToFuture => 'You cannot navigate into the future';

  @override
  String noGoalForDate(String date) {
    return 'No nutrition goal found for $date';
  }

  @override
  String get infoCopyright => '© 2025 Thorsten Rieß · dietry.de';

  @override
  String get offlineMode =>
      'Offline – changes will sync when connection is restored';

  @override
  String get pendingSyncCount => 'changes pending sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get appBarTitle => 'Dietry';

  @override
  String get profileTooltip => 'Profile';

  @override
  String get infoTooltip => 'Info & Legal Notice';

  @override
  String get languageTooltip => 'Change language';

  @override
  String get logoutTooltip => 'Logout';

  @override
  String get accountSectionTitle => 'Account & Data';

  @override
  String get exportDataButton => 'Export data';

  @override
  String get exportDataDescription => 'Download all your entries as CSV files';

  @override
  String get deleteAccountButton => 'Delete account';

  @override
  String get deleteAccountDescription =>
      'Permanently delete all your data and sign out';

  @override
  String get deleteAccountConfirmTitle => 'Really delete account?';

  @override
  String get deleteAccountConfirmText =>
      'All your food entries, activities, body measurements and goals will be permanently deleted. This action cannot be undone.';

  @override
  String get deleteAccountConfirmButton => 'Delete permanently';

  @override
  String get deleteAccountCredentialsHint =>
      'Note: Due to current limitations of the authentication provider (Neon Auth), your login credentials cannot be removed automatically along with your data. Please contact support if you also need those removed.';

  @override
  String get deleteAccountSuccess => 'All data has been deleted.';

  @override
  String get exportDataSuccess => 'Export successful';

  @override
  String exportDataError(String error) {
    return 'Export failed: $error';
  }

  @override
  String deleteAccountError(String error) {
    return 'Deletion failed: $error';
  }

  @override
  String get emailVerificationTitle => 'Check your inbox!';

  @override
  String emailVerificationBody(String email) {
    return 'We sent a confirmation link to $email. Please click it to activate your account, then sign in.';
  }

  @override
  String get emailVerificationBack => 'Back to sign in';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get resetLinkSent => 'Link sent!';

  @override
  String resetLinkSentBody(String email) {
    return 'We sent a password reset link to $email.';
  }

  @override
  String get waterTitle => 'Water intake';

  @override
  String waterGoalLabel(int amount) {
    return 'Goal: $amount ml';
  }

  @override
  String get waterAdd => 'Add water';

  @override
  String get waterRemove => 'Remove water';

  @override
  String get devBannerText =>
      '⚠️ Preview build · Development database · Data is not permanently stored';

  @override
  String get guestModeBannerText =>
      '👤 Guest mode · Data stored locally · Sign in to sync';

  @override
  String get waterGoalFieldLabel => 'Water goal';

  @override
  String get waterGoalFieldHint =>
      'Recommended: approx. 35 ml per kg body weight';

  @override
  String get waterReminderTitle => 'Drink reminders';

  @override
  String get waterReminderSubtitle => 'Remind to drink water every 4 hours';

  @override
  String get waterFromFood => 'from food';

  @override
  String get waterManual => 'manual';

  @override
  String get cheatDayTitle => 'Cheat Day';

  @override
  String get cheatDayBanner =>
      'Cheat Day! Enjoy yourself — excluded from reports.';

  @override
  String get markAsCheatDay => 'Cheat Day';

  @override
  String get cheatDayMarked => 'Cheat day marked ✓';

  @override
  String get cheatDayRemoved => 'Cheat day removed';

  @override
  String cheatDayMonthlyNudge(int count) {
    return 'You\'ve had $count cheat days this month. All good, no judgement!';
  }

  @override
  String streakDays(int count) {
    return '$count day streak';
  }

  @override
  String get streakStart => 'Start your streak today!';

  @override
  String streakBestLabel(int count) {
    return 'Best: $count';
  }

  @override
  String get streakMilestoneTitle => 'Milestone reached!';

  @override
  String streakMilestoneBody(int count) {
    return 'You\'ve completed a $count-day streak. Keep it up!';
  }

  @override
  String get serverConfigButton => 'Server configuration';

  @override
  String get serverConfigTitle => 'Server configuration';

  @override
  String get serverConfigDescription =>
      'For self-hosted installations you can point the app to your own Neon PostgREST and Auth endpoints. Leave unchanged to use the default managed server.';

  @override
  String get serverConfigDataApiUrl => 'PostgREST API URL';

  @override
  String get serverConfigAuthBaseUrl => 'Auth base URL';

  @override
  String get serverConfigCustomActive =>
      'Custom server active — using your own endpoints.';

  @override
  String get serverConfigReset => 'Reset to defaults';

  @override
  String get feedbackTitle => 'Send Feedback';

  @override
  String get feedbackTooltip => 'Send feedback';

  @override
  String get feedbackEarlyAccessNote =>
      'You\'re using an early access version. Your feedback helps us improve!';

  @override
  String get feedbackTypeLabel => 'Type';

  @override
  String get feedbackTypeBug => 'Bug';

  @override
  String get feedbackTypeFeature => 'Feature request';

  @override
  String get feedbackTypeGeneral => 'General';

  @override
  String get feedbackRatingLabel => 'Rating (optional)';

  @override
  String get feedbackMessageLabel => 'Message';

  @override
  String get feedbackMessageHint =>
      'Describe the bug, your idea, or your experience…';

  @override
  String get feedbackMessageTooShort => 'Please enter at least 10 characters.';

  @override
  String get feedbackSubmit => 'Submit';

  @override
  String get feedbackThankYou => 'Thank you for your feedback!';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsRangeWeek => 'Week';

  @override
  String get reportsRangeMonth => 'Month';

  @override
  String get reportsRangeYear => 'Year';

  @override
  String get reportsRangeAllTime => 'All time';

  @override
  String get reportsSummary => 'Summary';

  @override
  String get reportsCalorieTrend => 'Calorie Trend';

  @override
  String get reportsMacroAverage => 'Average Macros';

  @override
  String get reportsWaterIntake => 'Water Intake';

  @override
  String get reportsBodyWeight => 'Body Weight';

  @override
  String get reportsMostEatenFoods => 'Top Foods';

  @override
  String get reportsSortCalories => 'kcal';

  @override
  String get reportsSortCount => 'Count';

  @override
  String get reportsSortWeight => 'Weight';

  @override
  String get reportsNoData => 'No data for this period.';

  @override
  String get reportsAvgCalories => 'Avg. daily calories';

  @override
  String get reportsDaysTracked => 'Days tracked';

  @override
  String get reportsDaysOnTarget => 'Days on target';

  @override
  String get reportsAvgWater => 'Avg. daily water';

  @override
  String get reportsGoalLine => 'Goal';

  @override
  String get reportsBodyFat => 'Body fat %';

  @override
  String get reportsCaloriesBurned => 'Burned';

  @override
  String get reportsConsumed => 'Consumed';

  @override
  String get reportsBalance => 'Balance';

  @override
  String get reportsUpsellBasic => 'Available in Cloud Edition';

  @override
  String get reportsUpsellPro => 'Available for Pro users';

  @override
  String get reportsLoading => 'Loading reports…';

  @override
  String get reportsExportTooltip => 'Export as CSV';

  @override
  String get reportsExportSuccess => 'Export successful';

  @override
  String reportsExportError(String error) {
    return 'Export failed: $error';
  }

  @override
  String get macroOnlyMode => 'Track macros only (no calorie goal)';

  @override
  String caloriesTooMuch(String amount) {
    return '$amount too much';
  }

  @override
  String get shareProgressTitle => 'Share Your Progress';

  @override
  String get shareTabStreak => '🔥 Streak';

  @override
  String get shareTabDaily => '📊 Daily Goals';

  @override
  String get shareButton => 'Share to Social Media';

  @override
  String get sharing => 'Sharing...';

  @override
  String get shareHashtags => '#Dietry #NutritionTracking #HealthyLifestyle';

  @override
  String shareStreakCaption(int days) {
    return '🔥 I\'m on a $days-day streak tracking my nutrition!';
  }

  @override
  String get streakDayText => 'day';

  @override
  String get shareStreakCaptionEnd => ' tracking my nutrition!';

  @override
  String get shareDailyCaption => '✅ Met my nutrition goals today!';

  @override
  String get shareSuccessful => '✅ Shared successfully!';

  @override
  String get shareFailed => '❌ Sharing failed. Please try again.';

  @override
  String get logFood => 'Log Food';

  @override
  String get nutritionInfo => 'Nutrition Info';

  @override
  String get per100g => 'per 100g';

  @override
  String get tags => 'Tags';

  @override
  String get addTag => 'Add Tag';

  @override
  String get tagHint => 'e.g., vegetarian, vegan, raw...';

  @override
  String get filterByTag => 'Filter by tag';

  @override
  String get deleteGuestDataTitle => 'Delete Guest Data';

  @override
  String get deleteGuestDataConfirm =>
      'All your guest data (entries, goals, profile) will be deleted and cannot be recovered. Continue?';

  @override
  String get deleteGuestDataSuccess => '✅ All guest data deleted';

  @override
  String get migrationDialogTitle => 'Transfer Guest Data?';

  @override
  String get migrationDialogContent =>
      'You had entries in guest mode. These can be transferred to your account.';

  @override
  String get migrationTransfer => 'Transfer';

  @override
  String get migrationDiscard => 'Discard';

  @override
  String migrationSuccess(int count) {
    return '✅ $count entries transferred';
  }

  @override
  String get migrationError =>
      '⚠️ Migration error (entries can be transferred manually)';
}
