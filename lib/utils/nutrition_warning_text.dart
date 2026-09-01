import '../l10n/app_localizations.dart';
import '../models/food_search_result.dart';

/// One line naming what looks wrong about an online source's nutrition values,
/// or null when nothing does.
///
/// Several warnings collapse into the most serious one: this interrupts someone
/// mid-log, so a single sentence is the whole budget.
String? nutritionWarningText(
  List<NutritionDataWarning> warnings,
  AppLocalizations l,
) {
  if (warnings.contains(NutritionDataWarning.impossibleValues)) {
    return l.foodValuesImpossible;
  }
  if (warnings.contains(NutritionDataWarning.energyMismatch)) {
    return l.foodValuesEnergyMismatch;
  }
  return null;
}
