import 'neon_database_service.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

class DailyNutritionData {
  final DateTime date;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const DailyNutritionData({
    required this.date,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });
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

    var q = _db.client
        .from('daily_nutrition_summary')
        .select('entry_date,total_calories,total_protein,total_fat,total_carbs')
        .eq('user_id', uid)
        .lte('entry_date', _ds(to));
    if (from != null) q = q.gte('entry_date', _ds(from));
    final qSorted = q.order('entry_date', ascending: true);

    final r = await qSorted;
    return (r as List)
        .map((row) => DailyNutritionData(
              date: DateTime.parse(row['entry_date'] as String),
              calories: (row['total_calories'] as num?)?.toDouble() ?? 0,
              protein: (row['total_protein'] as num?)?.toDouble() ?? 0,
              fat: (row['total_fat'] as num?)?.toDouble() ?? 0,
              carbs: (row['total_carbs'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
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
