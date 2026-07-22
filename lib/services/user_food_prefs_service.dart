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

  /// User-measured cooked weight ÷ raw weight for this food. Null = fall back
  /// to the app's generic factor from [CookingYield].
  final double? cookedFactor;

  const UserFoodPref({
    required this.amount,
    required this.unit,
    this.cookedFactor,
  });
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
          .select('food_id,last_amount,last_unit,cooked_factor')
          .eq('user_id', userId)
          .filter('food_id', 'in', '($inList)');
      final out = <String, UserFoodPref>{};
      for (final row in (response as List)) {
        final m = row as Map<String, dynamic>;
        out[m['food_id'] as String] = UserFoodPref(
          amount: (m['last_amount'] as num).toDouble(),
          unit: m['last_unit'] as String,
          cookedFactor: (m['cooked_factor'] as num?)?.toDouble(),
        );
      }
      return out;
    } catch (e) {
      appLogger.d('UserFoodPrefsService.getForFoodIds failed: $e');
      return const {};
    }
  }

  /// Stores a user-measured cooked/raw yield factor for [foodId].
  ///
  /// [amount] and [unit] are required because the row may not exist yet and
  /// both columns are NOT NULL — on insert they seed the portion memory, on
  /// conflict they are refreshed alongside the factor.
  ///
  /// Unlike [upsert] this is user-initiated, so it reports success: the caller
  /// shows the result of an explicit action rather than silently dropping it.
  /// A null [factor] clears the measurement and falls back to the generic one.
  Future<bool> upsertCookedFactor({
    required String foodId,
    required double? factor,
    required double amount,
    required String unit,
  }) async {
    try {
      final tokenValid = await _db.ensureValidToken(minMinutesValid: 5);
      if (!tokenValid) return false;
      final userId = _db.userId;
      if (userId == null) return false;
      await _db.dioClient.post(
        '/user_food_prefs',
        data: {
          'user_id': userId,
          'food_id': foodId,
          'last_amount': amount,
          'last_unit': unit,
          'cooked_factor': factor,
          'updated_at': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        }),
      );
      return true;
    } catch (e) {
      appLogger.w('UserFoodPrefsService.upsertCookedFactor failed: $e');
      return false;
    }
  }

  /// Upserts the user's preference for [foodId] with the [amount] and [unit]
  /// they just logged. Fire-and-forget from callers — failures are logged
  /// but never thrown, so a pref hiccup can't break the food-add flow.
  ///
  /// NOTE: deliberately omits `cooked_factor`. PostgREST builds the
  /// `ON CONFLICT DO UPDATE SET` list from the payload's keys, so a column that
  /// isn't sent is left untouched — otherwise every ordinary food log would
  /// wipe the user's measured factor.
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
