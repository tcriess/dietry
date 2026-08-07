class CheatDay {
  final String id;
  final String userId;
  final DateTime cheatDate;
  final String? note;

  /// Groups the days belonging to one declared holiday. Null when the user
  /// toggled this single day by hand. See [Holiday].
  final String? holidayId;

  final DateTime createdAt;

  const CheatDay({
    required this.id,
    required this.userId,
    required this.cheatDate,
    this.note,
    this.holidayId,
    required this.createdAt,
  });

  /// Name to show for this day, or null when it is not part of a named
  /// holiday. A note on a hand-toggled day is not a holiday name, and an
  /// unnamed holiday has nothing to show.
  String? get holidayLabel {
    if (holidayId == null) return null;
    final n = note;
    return (n == null || n.isEmpty) ? null : n;
  }

  factory CheatDay.fromJson(Map<String, dynamic> json) {
    return CheatDay(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      cheatDate: DateTime.parse(json['cheat_date'] as String),
      note: json['note'] as String?,
      holidayId: json['holiday_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'cheat_date': cheatDate.toIso8601String().split('T')[0],
    if (note != null) 'note': note,
    if (holidayId != null) 'holiday_id': holidayId,
    'created_at': createdAt.toIso8601String(),
  };
}
