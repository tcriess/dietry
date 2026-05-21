double parseDouble(String s) => double.parse(s.replaceAll(',', '.'));

double? tryParseDouble(String? s) {
  if (s == null || s.isEmpty) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}

/// Formats an amount/count for display: whole numbers without decimals,
/// fractional values with a single decimal. e.g. 2.0 → "2", 1.5 → "1.5".
String formatAmount(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Scales a per-100(g/ml) nutrient value to the total for [grams].
double scaleToTotal(double per100, double grams) => per100 * grams / 100.0;

/// Derives a per-100(g/ml) nutrient value from a stored [total] that
/// corresponds to [grams]. Returns 0 when [grams] is not positive.
double toPer100g(double total, double grams) =>
    grams > 0 ? total * 100.0 / grams : 0;
