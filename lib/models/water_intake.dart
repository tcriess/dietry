class WaterIntake {
  final String? id;
  final String? userId;
  final DateTime date;
  final int amountMl;

  const WaterIntake({
    this.id,
    this.userId,
    required this.date,
    required this.amountMl,
  });

  factory WaterIntake.fromJson(Map<String, dynamic> json) {
    return WaterIntake(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      date: DateTime.parse(json['date'] as String),
      amountMl: (json['amount_ml'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (userId != null) 'user_id': userId,
    'date': date.toIso8601String().split('T')[0],
    'amount_ml': amountMl,
  };

  WaterIntake copyWith({int? amountMl}) => WaterIntake(
    id: id,
    userId: userId,
    date: date,
    amountMl: amountMl ?? this.amountMl,
  );
}
