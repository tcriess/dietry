import 'package:dio/dio.dart';
import '../models/streak_record.dart';
import 'neon_database_service.dart';

/// Manages the persistent streak record in `user_streaks` (cloud-only).
///
/// The computation of the current streak value is still done by
/// [CheatDayService.getStreak]. This service only persists the result,
/// tracks the all-time best, and detects newly reached milestones so the
/// UI can show a one-time celebration.
class StreakService {
  final NeonDatabaseService _db;

  StreakService(this._db);

  /// Milestone values that trigger a celebration when first reached.
  static const milestones = [3, 7, 14, 30, 60, 100, 365];

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Loads the persisted streak record for the current user.
  /// Returns null if no record exists yet.
  Future<StreakRecord?> loadRecord() async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return null;
    final userId = _db.userId;
    if (userId == null) return null;

    final response = await _db.client
        .from('user_streaks')
        .select()
        .eq('user_id', userId);

    final list = response as List;
    if (list.isEmpty) return null;
    return StreakRecord.fromJson(list.first as Map<String, dynamic>);
  }

  /// Persists [newStreak] to `user_streaks`, updates the all-time best,
  /// and returns the list of **newly** reached milestones (not seen before).
  ///
  /// Call this after any tracking action (food entry added, cheat day toggled).
  Future<List<int>> updateRecord(int newStreak) async {
    if (!await _db.ensureValidToken(minMinutesValid: 5)) return [];
    final userId = _db.userId;
    if (userId == null) return [];

    final existing = await loadRecord();
    final oldBest = existing?.bestStreak ?? 0;
    final alreadyReached = existing?.milestonesReached ?? [];

    final newBest = newStreak > oldBest ? newStreak : oldBest;
    final newlyReached = milestones
        .where((m) => newStreak >= m && !alreadyReached.contains(m))
        .toList();
    final updatedMilestones = [...alreadyReached, ...newlyReached];

    final payload = {
      'user_id': userId,
      'current_streak': newStreak,
      'best_streak': newBest,
      'last_tracked_date': _dateStr(DateTime.now()),
      'milestones_reached': updatedMilestones,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    // UPSERT via Dio
    await _db.dioClient.post(
      '/user_streaks',
      data: payload,
      options: Options(headers: {'Prefer': 'resolution=merge-duplicates,return=minimal'}),
    );

    return newlyReached;
  }
}
