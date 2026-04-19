double parseDouble(String s) => double.parse(s.replaceAll(',', '.'));

double? tryParseDouble(String? s) {
  if (s == null || s.isEmpty) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}
