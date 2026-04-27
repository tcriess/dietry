import 'neon_database_service.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

class FoodFrequencyItem {
  final String name;
  final String? foodId;
  final int count;
  final double totalCalories;
  final double totalWeightG;

  const FoodFrequencyItem({
    required this.name,
    this.foodId,
    required this.count,
    required this.totalCalories,
    required this.totalWeightG,
  });
}

class DailyNutritionData {
  final DateTime date;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double caloriesBurned;

  const DailyNutritionData({
    required this.date,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.caloriesBurned = 0,
  });

  double get netCalories => calories - caloriesBurned;
}

class DailyWaterData {
  final DateTime date;
  final int amountMl;

  const DailyWaterData({required this.date, required this.amountMl});
}

class WeightEntry {
  final DateTime date;
  final double weight;
  final double? bodyFatPct;

  const WeightEntry({required this.date, required this.weight, this.bodyFatPct});
}

// ── Service ───────────────────────────────────────────────────────────────────

class ReportsService {
  final NeonDatabaseService _db;

  ReportsService(this._db);

  String _ds(DateTime d) => d.toIso8601String().split('T')[0];
  String? get _uid => _db.userId;
  Future<bool> _tok() => _db.ensureValidToken(minMinutesValid: 5);

  // ── Nutrition (CE) ─────────────────────────────────────────────────────────

  Future<List<DailyNutritionData>> getNutritionTrend(
      DateTime? from, DateTime to) async {
    if (!await _tok()) return [];
    final uid = _uid;
    if (uid == null) return [];

    var qN = _db.client
        .from('daily_nutrition_summary')
        .select('entry_date,total_calories,total_protein,total_fat,total_carbs')
        .eq('user_id', uid)
        .lte('entry_date', _ds(to));
    if (from != null) qN = qN.gte('entry_date', _ds(from));
    final rN = await qN.order('entry_date', ascending: true);

    var qA = _db.client
        .from('daily_activity_summary')
        .select('activity_date,total_calories')
        .eq('user_id', uid)
        .lte('activity_date', _ds(to));
    if (from != null) qA = qA.gte('activity_date', _ds(from));
    final rA = await qA;

    final burnedByDate = <String, double>{};
    for (final row in rA as List) {
      final ds = (row['activity_date'] as String).split('T')[0];
      burnedByDate[ds] =
          (row['total_calories'] as num?)?.toDouble() ?? 0;
    }

    return (rN as List).map((row) {
      final ds = (row['entry_date'] as String).split('T')[0];
      return DailyNutritionData(
        date: DateTime.parse(row['entry_date'] as String),
        calories: (row['total_calories'] as num?)?.toDouble() ?? 0,
        protein: (row['total_protein'] as num?)?.toDouble() ?? 0,
        fat: (row['total_fat'] as num?)?.toDouble() ?? 0,
        carbs: (row['total_carbs'] as num?)?.toDouble() ?? 0,
        caloriesBurned: burnedByDate[ds] ?? 0,
      );
    }).toList();
  }

  // ── Water (CE) ─────────────────────────────────────────────────────────────

  Future<List<DailyWaterData>> getWaterTrend(
      DateTime? from, DateTime to) async {
    if (!await _tok()) return [];
    final uid = _uid;
    if (uid == null) return [];

    var q = _db.client
        .from('water_intake')
        .select('date,amount_ml')
        .eq('user_id', uid)
        .lte('date', _ds(to));
    if (from != null) q = q.gte('date', _ds(from));

    final r = await q.order('date', ascending: true);
    return (r as List)
        .map((row) => DailyWaterData(
              date: DateTime.parse(row['date'] as String),
              amountMl: (row['amount_ml'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  // ── Most eaten foods (CE) ──────────────────────────────────────────────────

  Future<List<FoodFrequencyItem>> getMostEatenFoods(
      DateTime? from, DateTime to) async {
    if (!await _tok()) return [];
    final uid = _uid;
    if (uid == null) return [];

    var q = _db.client
        .from('food_entries')
        .select('name,food_id,amount,unit,calories')
        .eq('user_id', uid)
        .eq('is_liquid', false)
        .eq('is_meal', false)
        .lte('entry_date', _ds(to));
    if (from != null) q = q.gte('entry_date', _ds(from));

    final r = await q;
    final Map<String, ({String name, String? foodId, int count, double totalCal, double totalWeightG})> agg = {};

    for (final row in r as List) {
      final fid = row['food_id'] as String?;
      final name = row['name'] as String;
      final key = fid ?? name;
      final cal = (row['calories'] as num?)?.toDouble() ?? 0;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final unit = (row['unit'] as String?) ?? '';
      final weightG = (unit == 'g' || unit == 'gram' || unit == 'grams') ? amount : 0.0;

      if (agg.containsKey(key)) {
        final prev = agg[key]!;
        agg[key] = (
          name: prev.name,
          foodId: prev.foodId,
          count: prev.count + 1,
          totalCal: prev.totalCal + cal,
          totalWeightG: prev.totalWeightG + weightG,
        );
      } else {
        agg[key] = (name: name, foodId: fid, count: 1, totalCal: cal, totalWeightG: weightG);
      }
    }

    return agg.values
        .map((e) => FoodFrequencyItem(
              name: e.name,
              foodId: e.foodId,
              count: e.count,
              totalCalories: e.totalCal,
              totalWeightG: e.totalWeightG,
            ))
        .toList();
  }

  // ── Body weight (CE) ───────────────────────────────────────────────────────

  Future<List<WeightEntry>> getWeightTrend(
      DateTime? from, DateTime to) async {
    if (!await _tok()) return [];
    final uid = _uid;
    if (uid == null) return [];

    var q = _db.client
        .from('user_body_measurements')
        .select('measured_at,weight,body_fat_percentage')
        .eq('user_id', uid)
        .lte('measured_at', _ds(to));
    if (from != null) q = q.gte('measured_at', _ds(from));

    final r = await q.order('measured_at', ascending: true);
    return (r as List)
        .map((row) => WeightEntry(
              date: DateTime.parse(row['measured_at'] as String),
              weight: (row['weight'] as num).toDouble(),
              bodyFatPct: row['body_fat_percentage'] != null
                  ? (row['body_fat_percentage'] as num).toDouble()
                  : null,
            ))
        .toList();
  }

}
