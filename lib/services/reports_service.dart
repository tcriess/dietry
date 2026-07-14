import '../models/gear.dart';
import 'gear_service.dart';
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

/// One gear item on the reports page: what it did in the selected range, and
/// what it has done in its life. The two are deliberately kept apart — the
/// range answers "what did I train on", the lifetime answers "when do I replace
/// this", and only the latter may include [Gear.initialDistanceKm].
class GearReportItem {
  final Gear gear;
  final GearTotals lifetime;
  final double rangeKm;
  final int rangeMinutes;
  final int rangeCount;

  const GearReportItem({
    required this.gear,
    required this.lifetime,
    this.rangeKm = 0,
    this.rangeMinutes = 0,
    this.rangeCount = 0,
  });

  bool get usedInRange => rangeCount > 0;
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

  // ── Gear (CE) ──────────────────────────────────────────────────────────────

  /// Per-gear usage in [from]..[to], paired with lifetime totals.
  ///
  /// The range half is aggregated here rather than in SQL (same as
  /// [getMostEatenFoods]); the lifetime half comes from the `get_gear_totals()`
  /// RPC, because it must span the user's whole history and include the
  /// pre-tracking `initial_distance_km`.
  ///
  /// Empty when the user owns no gear — the reports page then omits the card
  /// entirely instead of showing an empty one.
  Future<List<GearReportItem>> getGearReport(
      DateTime? from, DateTime to) async {
    if (!await _tok()) return [];
    final uid = _uid;
    if (uid == null) return [];

    final gearSvc = GearService(_db);
    final gear = await gearSvc.getGear();
    if (gear.isEmpty) return [];

    // `to` is an inclusive date, start_time a timestamp — bound with the
    // exclusive next midnight so the last day's activities are not cut off.
    final toExclusive = DateTime(to.year, to.month, to.day)
        .add(const Duration(days: 1));

    var q = _db.client
        .from('physical_activities')
        .select('gear_id,distance_km,duration_minutes')
        .eq('user_id', uid)
        .not('gear_id', 'is', null)
        .lt('start_time', _ds(toExclusive));
    if (from != null) q = q.gte('start_time', _ds(from));

    final results = await Future.wait<dynamic>([gearSvc.getTotals(), q]);

    return buildGearReport(
      gear: gear,
      lifetime: results[0] as Map<String, GearTotals>,
      activityRows: (results[1] as List).cast<Map<String, dynamic>>(),
    );
  }

}

// ── Gear report assembly (pure) ───────────────────────────────────────────────

/// Folds the raw ingredients of the gear report into the rows the card renders:
/// the user's [gear], their [lifetime] totals keyed by gear id, and the
/// [activityRows] of the selected range (`gear_id`, `distance_km`,
/// `duration_minutes` — exactly the columns [ReportsService.getGearReport]
/// selects).
///
/// Pure and separated from the fetch so the aggregation, the retired-gear rule
/// and the sort order can be tested without a database.
List<GearReportItem> buildGearReport({
  required List<Gear> gear,
  required Map<String, GearTotals> lifetime,
  required Iterable<Map<String, dynamic>> activityRows,
}) {
  final Map<String, ({double km, int minutes, int count})> agg = {};
  for (final row in activityRows) {
    final gid = row['gear_id'] as String?;
    if (gid == null) continue;
    final cur = agg[gid] ?? (km: 0.0, minutes: 0, count: 0);
    agg[gid] = (
      // Distance is null for gym work; such an activity still counts as a use.
      km: cur.km + ((row['distance_km'] as num?)?.toDouble() ?? 0),
      minutes: cur.minutes + ((row['duration_minutes'] as num?)?.toInt() ?? 0),
      count: cur.count + 1,
    );
  }

  final items = <GearReportItem>[];
  for (final g in gear) {
    final id = g.id;
    if (id == null) continue;
    final r = agg[id];
    // Retired gear only earns a row if it was actually used in the range;
    // otherwise the card fills up with things the user has already replaced.
    if (g.retired && r == null) continue;
    items.add(GearReportItem(
      gear: g,
      lifetime: lifetime[id] ?? GearTotals(gearId: id),
      rangeKm: r?.km ?? 0,
      rangeMinutes: r?.minutes ?? 0,
      rangeCount: r?.count ?? 0,
    ));
  }

  // Used-in-range first (a gym item with 0 km but 5 sessions still outranks an
  // untouched pair of shoes), then by distance, then by time, then by lifetime.
  items.sort((a, b) {
    if (a.usedInRange != b.usedInRange) return a.usedInRange ? -1 : 1;
    final byKm = b.rangeKm.compareTo(a.rangeKm);
    if (byKm != 0) return byKm;
    final byMin = b.rangeMinutes.compareTo(a.rangeMinutes);
    if (byMin != 0) return byMin;
    return b.lifetime.totalDistanceKm.compareTo(a.lifetime.totalDistanceKm);
  });
  return items;
}
