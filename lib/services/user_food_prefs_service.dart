import 'package:dietry/services/app_logger.dart';
import 'package:dio/dio.dart';
import 'neon_database_service.dart';

/// Per-user portion preferences for foods. Backed by the `user_food_prefs`
/// table (see sql/28_user_food_prefs.sql). Stores the amount + unit the user
/// last logged for each food so the quick-add path can pre-fill their
/// typical portion instead of the food's generic serving size — works for
/// public foods too because state is keyed by (user_id, food_id), not by
/// food ownership.
class UserFoodPref {
  final double amount;
  final String unit;

  const UserFoodPref({required this.amount, required this.unit});
}

class UserFoodPrefsService {
  final NeonDatabaseService _db;

  UserFoodPrefsService(this._db);

  /// Batch-fetches the current user's prefs for [foodIds]. Returns a map
  /// keyed by food id; food ids without a stored pref are simply absent.
  /// Returns an empty map on any failure — the caller should fall back to
  /// the food's generic serving size.
  Future<Map<String, UserFoodPref>> getForFoodIds(List<String> foodIds) async {
    if (foodIds.isEmpty) return const {};
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return const {};
      final userId = _db.userId;
      if (userId == null) return const {};
      final inList = foodIds.map((id) => '"$id"').join(',');
      final response = await _db.client
          .from('user_food_prefs')
          .select('food_id,last_amount,last_unit')
          .eq('user_id', userId)
          .filter('food_id', 'in', '($inList)');
      final out = <String, UserFoodPref>{};
      for (final row in (response as List)) {
        final m = row as Map<String, dynamic>;
        out[m['food_id'] as String] = UserFoodPref(
          amount: (m['last_amount'] as num).toDouble(),
          unit: m['last_unit'] as String,
        );
      }
      return out;
    } catch (e) {
      appLogger.d('UserFoodPrefsService.getForFoodIds failed: $e');
      return const {};
    }
  }

  /// Upserts the user's preference for [foodId] with the [amount] and [unit]
  /// they just logged. Fire-and-forget from callers — failures are logged
  /// but never thrown, so a pref hiccup can't break the food-add flow.
  Future<void> upsert({
    required String foodId,
    required double amount,
    required String unit,
  }) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return;
      final userId = _db.userId;
      if (userId == null) return;
      await _db.dioClient.post(
        '/user_food_prefs',
        data: {
          'user_id': userId,
          'food_id': foodId,
          'last_amount': amount,
          'last_unit': unit,
          'updated_at': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        }),
      );
    } catch (e) {
      appLogger.d('UserFoodPrefsService.upsert failed: $e');
    }
  }
}
