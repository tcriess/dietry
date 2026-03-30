class CheatDay {
  final String id;
  final String userId;
  final DateTime cheatDate;
  final String? note;
  final DateTime createdAt;

  const CheatDay({
    required this.id,
    required this.userId,
    required this.cheatDate,
    this.note,
    required this.createdAt,
  });

  factory CheatDay.fromJson(Map<String, dynamic> json) {
    return CheatDay(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      cheatDate: DateTime.parse(json['cheat_date'] as String),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'cheat_date': cheatDate.toIso8601String().split('T')[0],
    if (note != null) 'note': note,
    'created_at': createdAt.toIso8601String(),
  };
}
