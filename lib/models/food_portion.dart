/// Benannte Portionsgröße eines Lebensmittels.
/// Wird in food_database.portions (JSONB) gespeichert.
class FoodPortion {
  final String name;    // z.B. "1 Scheibe", "1 Glas", "1 Stück"
  final double amountG; // Gramm- oder ml-Äquivalent für Nährwertberechnung

  const FoodPortion({required this.name, required this.amountG});

  factory FoodPortion.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final amountGRaw = json['amount_g'];

    if (name == null || name.isEmpty || amountGRaw == null) {
      throw FormatException(
        'Invalid FoodPortion: name=$name, amount_g=$amountGRaw',
      );
    }

    return FoodPortion(
      name: name,
      amountG: (amountGRaw as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'amount_g': amountG};

  @override
  String toString() => '$name (${amountG % 1 == 0 ? amountG.toInt() : amountG}g)';

  @override
  bool operator ==(Object other) =>
      other is FoodPortion && other.name == name && other.amountG == amountG;

  @override
  int get hashCode => Object.hash(name, amountG);
}
