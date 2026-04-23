import 'package:dietry_cloud/dietry_cloud.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_config.dart';
import '../app_features.dart';
import '../utils/app_features_utils.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/neon_database_service.dart';
import '../services/nutrition_goal_service.dart';
import '../services/platform_export.dart' as exporter;
import '../services/reports_service.dart';

enum _FoodSortMode { calories, count, weight }

// ── Time range ────────────────────────────────────────────────────────────────

enum ReportRange { week, month, year, allTime }

extension _RangeExt on ReportRange {
  (DateTime?, DateTime) get dates {
    final today = DateTime.now();
    // Exclude today — partial-day data is misleading in diagrams
    final to = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 1));
    return switch (this) {
      ReportRange.week => (to.subtract(const Duration(days: 6)), to),
      ReportRange.month => (to.subtract(const Duration(days: 29)), to),
      ReportRange.year => (to.subtract(const Duration(days: 364)), to),
      ReportRange.allTime => (null, to),
    };
  }

  /// Group daily points into display buckets.
  /// Week/month → daily; year → weekly avg; allTime → monthly avg.
  String bucketKey(DateTime d) => switch (this) {
        ReportRange.week || ReportRange.month => d.toIso8601String().split('T')[0],
        ReportRange.year =>
          '${d.year}-${(d.difference(DateTime(d.year)).inDays ~/ 7).toString().padLeft(2, '0')}',
        ReportRange.allTime => '${d.year}-${d.month.toString().padLeft(2, '0')}',
      };
}

// ── Aggregation helpers ───────────────────────────────────────────────────────

/// Returns the calorie goal valid on [date], or null if none found.
/// [goals] must be sorted descending by validFrom (as returned by getAllGoals()).
double? _goalCalForDate(List<NutritionGoal> goals, DateTime date) {
  for (final g in goals) {
    final from = g.validFrom;
    if (from == null || !from.isAfter(date)) {
      return g.calories > 0 ? g.calories : null;
    }
  }
  return null;
}

List<({DateTime date, double value})> _bucket(
    List<({DateTime date, double value})> pts, ReportRange range) {
  if (range == ReportRange.week || range == ReportRange.month) return pts;
  final Map<String, List<({DateTime date, double value})>> groups = {};
  for (final p in pts) {
    groups.putIfAbsent(range.bucketKey(p.date), () => []).add(p);
  }
  return groups.entries.map((e) {
    final avg = e.value.fold(0.0, (s, p) => s + p.value) / e.value.length;
    return (date: e.value.first.date, value: avg);
  }).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}


// ── Loaded data container ─────────────────────────────────────────────────────

class _ReportsData {
  final List<DailyNutritionData> nutrition;
  final List<DailyWaterData> water;
  final List<WeightEntry> weight;
  final List<FoodFrequencyItem> mostEatenFoods;
  final List<NutritionGoal> goalHistory;

  const _ReportsData({
    required this.nutrition,
    required this.water,
    required this.weight,
    this.mostEatenFoods = const [],
    this.goalHistory = const [],
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ReportsScreen extends StatefulWidget {
  final NeonDatabaseService? dbService;
  final NutritionGoal? goal;
  /// Increment to trigger a data reload (e.g. when switching to this tab).
  final ValueNotifier<int>? refreshTrigger;

  const ReportsScreen({
    super.key,
    required this.dbService,
    this.goal,
    this.refreshTrigger,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportRange _range = ReportRange.week;
  late Future<_ReportsData> _future;
  late final ReportsService _svc;
  _ReportsData? _lastData;
  bool _exportBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.dbService != null) {
      _svc = ReportsService(widget.dbService!);
      // Assign directly — calling setState() in initState() is an anti-pattern
      // and initState runs before the first build anyway.
      _future = _load();
    } else {
      _future = Future.value(const _ReportsData(
        nutrition: [],
        water: [],
        weight: [],
      ));
    }
    widget.refreshTrigger?.addListener(_reload);
  }

  @override
  void didUpdateWidget(ReportsScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshTrigger != widget.refreshTrigger) {
      old.refreshTrigger?.removeListener(_reload);
      widget.refreshTrigger?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    // Deliberately don't clear _lastData: the FutureBuilder falls back to it
    // while the new future is in flight, so the fl_chart widgets stay mounted
    // instead of unmounting mid-animation (which hits "dirty widget in the
    // wrong build scope" when the AnimationController's tick fires after the
    // chart's element is gone).
    setState(() {
      _future = _load();
    });
  }

  static String _fmt(DateTime d) => d.toIso8601String().split('T')[0];

  Future<_ReportsData> _load() async {
    // In guest mode, dbService is null; return empty data
    if (widget.dbService == null) {
      return const _ReportsData(
        nutrition: [],
        water: [],
        weight: [],
      );
    }

    // Ensure token is valid before fetching data
    final tokenValid = await widget.dbService!.ensureValidToken(minMinutesValid: 5);
    if (!tokenValid) {
      throw Exception('Token validation failed');
    }

    final (from, to) = _range.dates;
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final results = await Future.wait([
      _svc.getNutritionTrend(from, to),
      _svc.getWaterTrend(from, to),
      _svc.getWeightTrend(from, todayDate),
      _svc.getMostEatenFoods(from, to),
      NutritionGoalService(widget.dbService!).getAllGoals(),
    ]);

    final result = _ReportsData(
      nutrition: results[0] as List<DailyNutritionData>,
      water: results[1] as List<DailyWaterData>,
      weight: results[2] as List<WeightEntry>,
      mostEatenFoods: results[3] as List<FoodFrequencyItem>,
      goalHistory: results[4] as List<NutritionGoal>,
    );
    _lastData = result;
    return result;
  }

  // ── Export (cloud-only, delegated to premiumFeatures) ────────────────────────

  Future<void> _export() async {
    final data = _lastData;
    if (data == null || widget.dbService == null) return;
    setState(() => _exportBusy = true);
    try {
      final l = AppLocalizations.of(context)!;
      final (from, to) = _range.dates;
      final success = await premiumFeatures.exportReportsData(
        ceExporter: exporter.exportCsvFiles,
        range: _range.name,
        role: AppFeatures.role,
        userId: widget.dbService!.userId ?? '',
        authToken: widget.dbService!.jwt ?? '',
        apiUrl: NeonDatabaseService.dataApiUrl,
        fromDate: from != null ? _fmt(from) : null,
        toDate: _fmt(to),
        nutritionRows: data.nutrition
            .map((d) => ReportsCloudNutritionRow(
                  date: _fmt(d.date),
                  calories: d.calories,
                  protein: d.protein,
                  fat: d.fat,
                  carbs: d.carbs,
                ))
            .toList(),
        waterRows: data.water
            .map((d) =>
                ReportsCloudWaterRow(date: _fmt(d.date), amountMl: d.amountMl))
            .toList(),
        weightRows: data.weight
            .map((d) => ReportsCloudWeightRow(
                  date: _fmt(d.date),
                  weight: d.weight,
                  bodyFatPct: d.bodyFatPct,
                ))
            .toList(),
        calorieGoal: widget.goal?.calories,
        proteinGoal: widget.goal?.protein,
        fatGoal: widget.goal?.fat,
        carbsGoal: widget.goal?.carbs,
        waterGoalMl: widget.goal?.waterGoalMl,
      );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.reportsExportSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reportsExportError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Range selector + export button
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ReportRange>(
                  segments: [
                    ButtonSegment(value: ReportRange.week, label: Text(l.reportsRangeWeek)),
                    ButtonSegment(value: ReportRange.month, label: Text(l.reportsRangeMonth)),
                    ButtonSegment(value: ReportRange.year, label: Text(l.reportsRangeYear)),
                    ButtonSegment(value: ReportRange.allTime, label: Text(l.reportsRangeAllTime)),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) {
                    setState(() => _range = s.first);
                    _reload();
                  },
                  style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
              if (AppFeatures.reportsExport) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: _exportBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  tooltip: l.reportsExportTooltip,
                  onPressed: (_lastData == null || _exportBusy) ? null : _export,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          FutureBuilder<_ReportsData>(
            future: _future,
            builder: (context, snap) {
              // Prefer fresh data; fall back to the last loaded data while a
              // new future is in flight so the chart widgets don't unmount.
              final data = snap.data ?? _lastData;
              if (data == null) {
                if (snap.hasError) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: Text(l.reportsLoading)),
                );
              }
              return _ReportsBody(
                data: data,
                range: _range,
                goal: widget.goal,
                userId: widget.dbService?.userId ?? '',
                authToken: widget.dbService?.jwt ?? '',
                role: AppFeatures.role,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Body (built once data is loaded) ─────────────────────────────────────────

class _ReportsBody extends StatelessWidget {
  final _ReportsData data;
  final ReportRange range;
  final NutritionGoal? goal;
  final String userId;
  final String authToken;
  final String role;

  const _ReportsBody({
    required this.data,
    required this.range,
    required this.goal,
    required this.userId,
    required this.authToken,
    required this.role,
  });

  static String _fmt(DateTime d) => d.toIso8601String().split('T')[0];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── CE charts ──────────────────────────────────────────────────────
        // Hide calorie-related reports in macro-only mode
        if (goal?.macroOnly != true) ...[
          _StatsSummaryCard(nutrition: data.nutrition, water: data.water, goal: goal),
          const SizedBox(height: 12),
          _CalorieTrendCard(
            nutrition: data.nutrition,
            range: range,
            goalHistory: data.goalHistory,
          ),
          const SizedBox(height: 12),
        ],
        _ReportCard(
          title: l.reportsMacroAverage,
          child: _MacroAverageRow(nutrition: data.nutrition),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          title: l.reportsWaterIntake,
          child: _WaterTrendChart(
              water: data.water, range: range, goal: goal),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          title: l.reportsBodyWeight,
          child: _WeightTrendChart(weight: data.weight, range: range),
        ),
        const SizedBox(height: 12),
        _MostEatenFoodsCard(foods: data.mostEatenFoods),

        // ── Cloud-only charts (activity, balance, meal timing, goal compliance)
        const SizedBox(height: 20),
        if (AppConfig.isCloudEdition) ...[
          premiumFeatures.buildReportsCloudSections(
            range: range.name,
            role: role,
            userId: userId,
            authToken: authToken,
            apiUrl: NeonDatabaseService.dataApiUrl,
            fromDate: range.dates.$1 != null ? _fmt(range.dates.$1!) : null,
            toDate: _fmt(range.dates.$2),
            nutritionRows: data.nutrition
                .map((d) => ReportsCloudNutritionRow(
                      date: _fmt(d.date),
                      calories: d.calories,
                      protein: d.protein,
                      fat: d.fat,
                      carbs: d.carbs,
                    ))
                .toList(),
            calorieGoal: goal?.calories,
            proteinGoal: goal?.protein,
            fatGoal: goal?.fat,
            carbsGoal: goal?.carbs,
            waterGoalMl: goal?.waterGoalMl,
          ),
          if (!AppFeatures.isPaid)
            AppFeaturesUtils.buildUpgradePrompt(
              context,
              feature: l.upgradeProTitle,
              description: l.upgradeProReportsDescription,
            ),
        ] else ...[
          _UpsellCard(message: l.reportsUpsellBasic, icon: Icons.directions_run),
          const SizedBox(height: 12),
          _UpsellCard(
              message: l.reportsUpsellPro,
              icon: Icons.workspace_premium_outlined),
        ],

        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Card wrapper ──────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReportCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Empty hint ────────────────────────────────────────────────────────────────

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.reportsNoData,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
      );
}

// ── Upsell card ───────────────────────────────────────────────────────────────

class _UpsellCard extends StatelessWidget {
  final String message;
  final IconData icon;

  const _UpsellCard({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon,
                size: 28,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            Icon(Icons.lock_outline,
                size: 16,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ── x-axis label helper ───────────────────────────────────────────────────────

// Axis labels: compact but always include both day and month so a bar
// under "15." isn't ambiguous about which month it belongs to.
String _xLabel(DateTime date, ReportRange range) => switch (range) {
      ReportRange.week => '${date.day}.${date.month}.',
      ReportRange.month => '${date.day}.${date.month}.',
      ReportRange.year => '${date.day}.${date.month}.',
      ReportRange.allTime => DateFormat('MMM yy').format(date),
    };

// Tooltip labels: more verbose than axis labels — room to show the year.
String _tooltipLabel(DateTime date, ReportRange range) => switch (range) {
      ReportRange.week => '${date.day}.${date.month}.${date.year}',
      ReportRange.month => '${date.day}.${date.month}.${date.year}',
      ReportRange.year => '${date.day}.${date.month}.${date.year}',
      ReportRange.allTime => DateFormat('MMMM yyyy').format(date),
    };

// Only show labels every N points to avoid crowding.
int _labelEvery(int total) {
  if (total <= 7) return 1;
  if (total <= 14) return 2;
  if (total <= 31) return 5;
  if (total <= 52) return 4;
  return 3;
}

// ── CE: Stats summary card ────────────────────────────────────────────────────

class _StatsSummaryCard extends StatelessWidget {
  final List<DailyNutritionData> nutrition;
  final List<DailyWaterData> water;
  final NutritionGoal? goal;

  const _StatsSummaryCard(
      {required this.nutrition, required this.water, required this.goal});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Exclude today from averages — the day is incomplete and skews stats.
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final completed = nutrition
        .where((d) => d.date.toIso8601String().split('T')[0] != todayStr)
        .toList();
    final n = completed.length;
    final avgCal =
        n == 0 ? 0.0 : completed.fold(0.0, (s, d) => s + d.calories) / n;
    final completedWater = water
        .where((d) => d.date.toIso8601String().split('T')[0] != todayStr)
        .toList();
    final avgWater = completedWater.isEmpty
        ? 0
        : (completedWater.fold(0, (s, d) => s + d.amountMl) /
                completedWater.length)
            .round();

    final calGoal = goal?.calories ?? 0;
    final daysOnTarget = calGoal > 0
        ? completed
            .where((d) {
              final r = d.calories / calGoal;
              return r >= 0.9 && r <= 1.1;
            })
            .length
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.reportsSummary,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        label: l.reportsAvgCalories,
                        value:
                            '${avgCal.round()} kcal')),
                Expanded(
                    child: _StatTile(
                        label: l.reportsDaysTracked, value: '$n')),
                if (daysOnTarget != null)
                  Expanded(
                      child: _StatTile(
                          label: l.reportsDaysOnTarget,
                          value: '$daysOnTarget')),
                Expanded(
                    child: _StatTile(
                        label: l.reportsAvgWater,
                        value: '${(avgWater / 1000).toStringAsFixed(1)} L')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      );
}

// ── CE: Calorie trend card (with line/bar toggle) ─────────────────────────────

class _CalorieTrendCard extends StatefulWidget {
  final List<DailyNutritionData> nutrition;
  final ReportRange range;
  final List<NutritionGoal> goalHistory;

  const _CalorieTrendCard(
      {required this.nutrition, required this.range, required this.goalHistory});

  @override
  State<_CalorieTrendCard> createState() => _CalorieTrendCardState();
}

class _CalorieTrendCardState extends State<_CalorieTrendCard> {
  bool _showBars = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l.reportsCalorieTrend,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false, icon: Icon(Icons.show_chart, size: 16)),
                    ButtonSegment(
                        value: true, icon: Icon(Icons.bar_chart, size: 16)),
                  ],
                  selected: {_showBars},
                  onSelectionChanged: (s) =>
                      setState(() => _showBars = s.first),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _showBars
                ? _CalorieTrendBarChart(
                    nutrition: widget.nutrition,
                    range: widget.range,
                    goalHistory: widget.goalHistory,
                  )
                : _CalorieTrendLineChart(
                    nutrition: widget.nutrition,
                    range: widget.range,
                    goalHistory: widget.goalHistory,
                  ),
          ],
        ),
      ),
    );
  }
}

// ── CE: Calorie trend – line chart ────────────────────────────────────────────

class _CalorieTrendLineChart extends StatelessWidget {
  final List<DailyNutritionData> nutrition;
  final ReportRange range;
  final List<NutritionGoal> goalHistory;

  const _CalorieTrendLineChart(
      {required this.nutrition, required this.range, required this.goalHistory});

  @override
  Widget build(BuildContext context) {
    final pts = _bucket(
      nutrition.map((d) => (date: d.date, value: d.calories)).toList(),
      range,
    );

    if (pts.isEmpty) return const _NoData();

    final goalSpots = pts.asMap().entries.expand<FlSpot>((e) {
      final g = _goalCalForDate(goalHistory, pts[e.key].date);
      return g != null ? [FlSpot(e.key.toDouble(), g)] : [];
    }).toList();

    final maxY = ([
          ...pts.map((p) => p.value),
          ...goalSpots.map((s) => s.y),
        ].reduce((a, b) => a > b ? a : b) *
            1.1)
        .ceilToDouble();

    final every = _labelEvery(pts.length);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: every.toDouble(),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= pts.length || idx % every != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(_xLabel(pts[idx].date, range),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt();
                final date = idx >= 0 && idx < pts.length
                    ? _tooltipLabel(pts[idx].date, range)
                    : '';
                return LineTooltipItem(
                  '$date\n${s.y.round()} kcal',
                  const TextStyle(fontSize: 12, color: Colors.white),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            // Consumed line
            LineChartBarData(
              spots: pts
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: Colors.blue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withValues(alpha: 0.08),
              ),
            ),
            // Goal reference line (step function — reflects historical goals)
            if (goalSpots.isNotEmpty)
              LineChartBarData(
                spots: goalSpots,
                isCurved: false,
                color: Colors.red.withValues(alpha: 0.45),
                barWidth: 1.5,
                dashArray: [6, 4],
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}

// ── CE: Calorie trend – bar chart ─────────────────────────────────────────────

class _CalorieTrendBarChart extends StatelessWidget {
  final List<DailyNutritionData> nutrition;
  final ReportRange range;
  final List<NutritionGoal> goalHistory;

  const _CalorieTrendBarChart(
      {required this.nutrition, required this.range, required this.goalHistory});

  @override
  Widget build(BuildContext context) {
    final pts = _bucket(
      nutrition.map((d) => (date: d.date, value: d.calories)).toList(),
      range,
    );

    if (pts.isEmpty) return const _NoData();

    final goalByIndex = List.generate(
        pts.length, (i) => _goalCalForDate(goalHistory, pts[i].date));
    final maxY = ([
          ...pts.map((p) => p.value),
          ...goalByIndex.whereType<double>(),
        ].reduce((a, b) => a > b ? a : b) *
            1.1)
        .ceilToDouble();

    final every = _labelEvery(pts.length);
    final barWidth = (280 / pts.length).clamp(4.0, 18.0);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final date = group.x >= 0 && group.x < pts.length
                    ? _tooltipLabel(pts[group.x].date, range)
                    : '';
                return BarTooltipItem(
                  '$date\n${rod.toY.round()} kcal',
                  const TextStyle(fontSize: 12, color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= pts.length || idx % every != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(_xLabel(pts[idx].date, range),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          barGroups: pts
              .asMap()
              .entries
              .map((e) {
                final goalForBar = goalByIndex[e.key];
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value,
                      color: Colors.blue.withValues(alpha: 0.75),
                      width: barWidth,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                      backDrawRodData: goalForBar != null
                          ? BackgroundBarChartRodData(
                              show: true,
                              toY: goalForBar,
                              color: Colors.red.withValues(alpha: 0.10),
                            )
                          : BackgroundBarChartRodData(show: false),
                    ),
                  ],
                );
              })
              .toList(),
        ),
      ),
    );
  }
}

// ── CE: Macro average ─────────────────────────────────────────────────────────

class _MacroAverageRow extends StatelessWidget {
  final List<DailyNutritionData> nutrition;

  const _MacroAverageRow({required this.nutrition});

  @override
  Widget build(BuildContext context) {
    if (nutrition.isEmpty) return const _NoData();

    final l = AppLocalizations.of(context)!;
    final n = nutrition.length;
    final protein = nutrition.fold(0.0, (s, d) => s + d.protein) / n;
    final fat = nutrition.fold(0.0, (s, d) => s + d.fat) / n;
    final carbs = nutrition.fold(0.0, (s, d) => s + d.carbs) / n;
    final total = protein + fat + carbs;

    return Column(
      children: [
        Row(
          children: [
            _MacroChip(
                label: l.nutrientProtein,
                value: protein,
                color: Colors.green.shade600),
            const SizedBox(width: 8),
            _MacroChip(
                label: l.nutrientFat,
                value: fat,
                color: Colors.orange.shade600),
            const SizedBox(width: 8),
            _MacroChip(
                label: l.nutrientCarbs,
                value: carbs,
                color: Colors.purple.shade400),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Flexible(
                    flex: (protein / total * 100).round(),
                    child: Container(height: 8, color: Colors.green.shade600)),
                Flexible(
                    flex: (fat / total * 100).round(),
                    child: Container(height: 8, color: Colors.orange.shade600)),
                Flexible(
                    flex: (carbs / total * 100).round(),
                    child:
                        Container(height: 8, color: Colors.purple.shade400)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Text('${value.round()} g',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 15)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ],
          ),
        ),
      );
}

// ── CE: Water trend ───────────────────────────────────────────────────────────

class _WaterTrendChart extends StatelessWidget {
  final List<DailyWaterData> water;
  final ReportRange range;
  final NutritionGoal? goal;

  const _WaterTrendChart(
      {required this.water, required this.range, this.goal});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pts = _bucket(
      water.map((d) => (date: d.date, value: d.amountMl.toDouble())).toList(),
      range,
    );

    if (pts.isEmpty) return const _NoData();

    final waterGoal = (goal?.waterGoalMl ?? 2000).toDouble();
    final maxY = ([...pts.map((p) => p.value), waterGoal].reduce((a, b) => a > b ? a : b) * 1.15).ceilToDouble();
    final every = _labelEvery(pts.length);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final date = group.x >= 0 && group.x < pts.length
                    ? _tooltipLabel(pts[group.x].date, range)
                    : '';
                return BarTooltipItem(
                  '$date\n${(rod.toY / 1000).toStringAsFixed(2)} L',
                  const TextStyle(fontSize: 12, color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= pts.length || idx % every != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(_xLabel(pts[idx].date, range),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: waterGoal,
                color: Colors.blue.withValues(alpha: 0.5),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 10, color: Colors.blue),
                  labelResolver: (_) => l.reportsGoalLine,
                ),
              ),
            ],
          ),
          barGroups: pts
              .asMap()
              .entries
              .map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: e.value.value >= waterGoal
                            ? Colors.blue
                            : Colors.blue.shade300,
                        width: (280 / pts.length).clamp(4, 20),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ── CE: Body weight trend ─────────────────────────────────────────────────────

class _WeightTrendChart extends StatelessWidget {
  final List<WeightEntry> weight;
  final ReportRange range;

  const _WeightTrendChart({required this.weight, required this.range});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (weight.isEmpty) return const _NoData();

    // Weight line
    final wPts = _bucket(
      weight.map((e) => (date: e.date, value: e.weight)).toList(),
      range,
    );
    // Body fat line (only if any entry has it)
    final hasBf = weight.any((e) => e.bodyFatPct != null);
    final bfPts = hasBf
        ? _bucket(
            weight
                .where((e) => e.bodyFatPct != null)
                .map((e) => (date: e.date, value: e.bodyFatPct!))
                .toList(),
            range,
          )
        : <({DateTime date, double value})>[];

    final allWeights = wPts.map((p) => p.value);
    final minW = allWeights.reduce((a, b) => a < b ? a : b) - 1;
    final maxW = allWeights.reduce((a, b) => a > b ? a : b) + 1;
    final wRange = maxW - minW;

    // Normalize both datasets to 0–100 scale for plotting
    final normalizedWPts = wPts
        .map((p) => (date: p.date, value: (p.value - minW) / wRange * 100))
        .toList();

    // Body fat normalized to its actual range
    double minBf = 0;
    double maxBf = 50;
    late List<({DateTime date, double value, int wPtsIndex})> normalizedBfPts;
    if (bfPts.isNotEmpty) {
      final allBf = bfPts.map((p) => p.value);
      minBf = allBf.reduce((a, b) => a < b ? a : b);
      maxBf = allBf.reduce((a, b) => a > b ? a : b);
      final bfRange = maxBf - minBf;
      normalizedBfPts = bfPts
          .map((p) => (
                date: p.date,
                value: bfRange > 0
                    ? (p.value - minBf) / bfRange * 100
                    : 50.0,
                wPtsIndex: wPts.indexWhere((w) => w.date == p.date),
              ))
          .toList();
    } else {
      normalizedBfPts = [];
    }

    final every = _labelEvery(wPts.length);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          minX: 0,
          maxX: (wPts.length - 1).toDouble(),
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final idx = barSpot.x.toInt();
                  final dateLabel = idx >= 0 && idx < wPts.length
                      ? _tooltipLabel(wPts[idx].date, range)
                      : '';
                  final isWeightLine = barSpot.barIndex == 0;
                  late String value;
                  if (isWeightLine) {
                    final actualWeight = minW + barSpot.y / 100 * wRange;
                    value = '$dateLabel\n${actualWeight.toStringAsFixed(1)} kg';
                  } else if (barSpot.barIndex == 1 && normalizedBfPts.isNotEmpty) {
                    final bfRange = maxBf - minBf;
                    final actualBf = minBf + barSpot.y / 100 * bfRange;
                    value = '$dateLabel\n${actualBf.toStringAsFixed(1)}%';
                  } else {
                    value = '$dateLabel\n${barSpot.y.toStringAsFixed(1)}';
                  }
                  return LineTooltipItem(value, const TextStyle(color: Colors.white));
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  '${(minW + v / 100 * wRange).round()} kg',
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            rightTitles: hasBf
                ? AxisTitles(
                    axisNameWidget: Text(l.reportsBodyFat,
                        style: const TextStyle(fontSize: 9)),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) {
                        final bfRange = maxBf - minBf;
                        final actualBf = minBf + v / 100 * bfRange;
                        return Text(
                          '${actualBf.round()}%',
                          style: const TextStyle(fontSize: 9),
                        );
                      },
                    ),
                  )
                : const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: every.toDouble(),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= wPts.length || idx % every != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(_xLabel(wPts[idx].date, range),
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: normalizedWPts
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.2,
              color: Colors.deepOrange,
              barWidth: 2,
              dotData: FlDotData(
                  show: wPts.length <= 10,
                  getDotPainter: (_, __, ___, ____) =>
                      FlDotCirclePainter(radius: 3, color: Colors.deepOrange)),
            ),
            if (normalizedBfPts.isNotEmpty)
              LineChartBarData(
                spots: normalizedBfPts
                    .map((p) => FlSpot(p.wPtsIndex.toDouble(), p.value))
                    .toList(),
                isCurved: true,
                curveSmoothness: 0.2,
                color: Colors.purple.shade300,
                barWidth: 1.5,
                dashArray: [4, 3],
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}


// ── CE: Most eaten foods card ─────────────────────────────────────────────────

class _MostEatenFoodsCard extends StatefulWidget {
  final List<FoodFrequencyItem> foods;

  const _MostEatenFoodsCard({required this.foods});

  @override
  State<_MostEatenFoodsCard> createState() => _MostEatenFoodsCardState();
}

class _MostEatenFoodsCardState extends State<_MostEatenFoodsCard> {
  _FoodSortMode _sort = _FoodSortMode.calories;

  List<FoodFrequencyItem> get _sorted {
    final items = [...widget.foods];
    switch (_sort) {
      case _FoodSortMode.calories:
        items.sort((a, b) => b.totalCalories.compareTo(a.totalCalories));
      case _FoodSortMode.count:
        items.sort((a, b) => b.count.compareTo(a.count));
      case _FoodSortMode.weight:
        items.sort((a, b) => b.totalWeightG.compareTo(a.totalWeightG));
    }
    return items.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.reportsMostEatenFoods,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ToggleButtons(
                  isSelected: [
                    _sort == _FoodSortMode.calories,
                    _sort == _FoodSortMode.count,
                    _sort == _FoodSortMode.weight,
                  ],
                  onPressed: (i) =>
                      setState(() => _sort = _FoodSortMode.values[i]),
                  constraints:
                      const BoxConstraints(minWidth: 52, minHeight: 28),
                  textStyle: const TextStyle(fontSize: 11),
                  children: [
                    Text(l.reportsSortCalories),
                    Text(l.reportsSortCount),
                    Text(l.reportsSortWeight),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.foods.isEmpty)
              const _NoData()
            else
              ..._buildRows(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRows(ThemeData theme) {
    final items = _sorted;
    if (items.isEmpty) return [const _NoData()];
    final maxVal = switch (_sort) {
      _FoodSortMode.calories => items.first.totalCalories,
      _FoodSortMode.count => items.first.count.toDouble(),
      _FoodSortMode.weight => items.first.totalWeightG,
    };
    return items.asMap().entries.map((e) {
      final item = e.value;
      final val = switch (_sort) {
        _FoodSortMode.calories => item.totalCalories,
        _FoodSortMode.count => item.count.toDouble(),
        _FoodSortMode.weight => item.totalWeightG,
      };
      final label = switch (_sort) {
        _FoodSortMode.calories => '${val.round()} kcal',
        _FoodSortMode.count => '${item.count}\u00d7',
        _FoodSortMode.weight => '${val.round()} g',
      };
      return _FoodFrequencyRow(
        rank: e.key + 1,
        name: item.name,
        fraction: maxVal > 0 ? (val / maxVal).clamp(0.0, 1.0) : 0.0,
        label: label,
        theme: theme,
      );
    }).toList();
  }
}

class _FoodFrequencyRow extends StatelessWidget {
  final int rank;
  final String name;
  final double fraction;
  final String label;
  final ThemeData theme;

  const _FoodFrequencyRow({
    required this.rank,
    required this.name,
    required this.fraction,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: fraction,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
