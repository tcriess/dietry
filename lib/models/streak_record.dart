/// Persistent streak record stored in `user_streaks` (cloud only).
class StreakRecord {
  final String userId;
  final int currentStreak;
  final int bestStreak;
  final DateTime? lastTrackedDate;
  final List<int> milestonesReached;
  final DateTime updatedAt;

  const StreakRecord({
    required this.userId,
    required this.currentStreak,
    required this.bestStreak,
    this.lastTrackedDate,
    required this.milestonesReached,
    required this.updatedAt,
  });

  factory StreakRecord.fromJson(Map<String, dynamic> json) {
    final rawMilestones = json['milestones_reached'];
    List<int> milestones = [];
    if (rawMilestones is List) {
      milestones = rawMilestones.whereType<int>().toList();
    }
    return StreakRecord(
      userId: json['user_id'] as String,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      lastTrackedDate: json['last_tracked_date'] != null
          ? DateTime.parse(json['last_tracked_date'] as String)
          : null,
      milestonesReached: milestones,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'current_streak': currentStreak,
    'best_streak': bestStreak,
    if (lastTrackedDate != null)
      'last_tracked_date': lastTrackedDate!.toIso8601String().split('T')[0],
    'milestones_reached': milestonesReached,
    'updated_at': updatedAt.toIso8601String(),
  };
}
