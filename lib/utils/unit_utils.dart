import 'package:dietry/l10n/app_localizations.dart';
import 'package:dietry/models/food_portion.dart';
import 'package:dietry/services/cooking_yield.dart';

/// Canonical unit tokens stored in `food_entries.unit`.
///
/// Named portions store their (localized, user-authored) name instead; these
/// three are the built-in units and must stay language-independent on disk so
/// switching the app locale can never break unit → grams resolution.
const String kUnitGram = 'g';
const String kUnitMl = 'ml';

/// Weight measured *after* cooking. Converted back to the raw/dry basis the
/// nutrition values are declared for via the food's [CookingYieldInfo].
const String kUnitGramCooked = 'g_cooked';

/// Units that already are a direct 1:1 weight/volume in the food's own basis.
bool isDirectWeightUnit(String unit) => unit == kUnitGram || unit == kUnitMl;

/// Display label for a built-in unit token or a portion name.
///
/// [distinguishRaw] makes plain grams read "g (roh/trocken)" — only worth doing
/// when a cooked option is offered alongside it, otherwise a bare "g" is
/// clearer.
String unitLabel(
  String unit,
  AppLocalizations l, {
  bool distinguishRaw = false,
}) {
  if (unit == kUnitGramCooked) return l.unitGramsCooked;
  if (unit == kUnitGram && distinguishRaw) return l.unitGramsRaw;
  return unit;
}

/// Converts [amount] of [unit] into grams **on the food's label basis** — i.e.
/// the number the per-100g values may be scaled by.
///
/// Returns null when the unit cannot be resolved: an unknown portion name, or a
/// cooked weight for a food we have no yield factor for. Callers must treat null
/// as "cannot compute" rather than zero.
///
/// A resolved [portion] wins over the unit token, because portion names are
/// user-authored and a portion may legitimately be *called* "g".
double? unitToGrams(
  double amount,
  String unit, {
  FoodPortion? portion,
  double? cookedFactor,
}) {
  if (portion != null) return amount * portion.amountG;
  if (isDirectWeightUnit(unit)) return amount;
  if (unit == kUnitGramCooked) {
    return cookedFactor == null
        ? null
        : CookingYield.toRawGrams(amount, cookedFactor);
  }
  return null;
}
