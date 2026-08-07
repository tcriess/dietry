import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/holiday.dart';
import '../services/app_logger.dart';
import '../services/calendar_service.dart';
import '../services/cheat_day_service.dart';
import '../services/local_data_service.dart';
import '../services/neon_database_service.dart';

/// Declare and manage holidays — named runs of cheat days, typically a
/// vacation planned before it starts.
///
/// The user picks a date range (future dates allowed, which the day-by-day
/// overview deliberately does not let you navigate to) and every day in it
/// becomes an ordinary cheat day tagged with a shared holiday id. That is why
/// there is no "holiday" row to edit here: removing a holiday just un-marks its
/// days, and un-marking one day inside it via the overview toggle is fine and
/// leaves the rest intact.
class HolidaysScreen extends StatefulWidget {
  final NeonDatabaseService dbService;

  const HolidaysScreen({super.key, required this.dbService});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  late final CheatDayService _service = CheatDayService(widget.dbService);
  List<Holiday> _holidays = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final holidays = await _service.listHolidays();
      if (!mounted) return;
      setState(() {
        _holidays = holidays;
        _loading = false;
      });
    } catch (e) {
      appLogger.e('❌ Failed to load holidays: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(AppLocalizations.of(context)!.holidayLoadError);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  /// [seed] pre-fills the range and the name from a calendar entry. The user
  /// still walks through the date picker and the name dialog: an all-day event
  /// is a hint about a holiday, not a declaration of one, and its end date
  /// depends on a calendar-provider convention we can only guess at
  /// (see `_toCalendarEvent`). Confirming beats guessing when getting it wrong
  /// silently drops a day out of the nutrition reports.
  Future<void> _addHoliday({CalendarEvent? seed}) async {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final range = await showDateRangePicker(
      context: context,
      // Wide enough for a holiday logged after the fact or planned well ahead.
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDateRange: seed == null
          ? DateTimeRange(start: today, end: today)
          : DateTimeRange(start: seed.start, end: seed.end),
      helpText: l.holidayAdd,
    );
    if (range == null || !mounted) return;

    final label = await _askLabel(initial: seed?.title);
    if (label == null || !mounted) return; // cancelled

    setState(() => _busy = true);
    try {
      final holiday = await _service.createHoliday(
        start: range.start,
        end: range.end,
        label: label.isEmpty ? null : label,
      );
      // Mirror into the local cache so those days already read as cheat days
      // offline and on the next cold start, before any server reconcile.
      await _mirrorCreate(holiday, label.isEmpty ? null : label);
      _snack(l.holidayCreated(holiday.dayCount));
      await _load();
    } catch (e) {
      appLogger.e('❌ Failed to create holiday: $e');
      _snack(l.holidaySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mirrorCreate(Holiday holiday, String? label) async {
    try {
      await LocalDataService.instance.createHoliday(
        holidayId: holiday.id,
        start: holiday.start,
        end: holiday.end,
        label: label,
      );
    } catch (e) {
      // The server write already succeeded; a stale cache self-corrects on the
      // next reconcile, so this must not fail the user's action.
      appLogger.w('⚠️ Could not mirror holiday locally: $e');
    }
  }

  /// Asks for an optional name. Returns null when cancelled, '' when skipped.
  Future<String?> _askLabel({String? initial}) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.holidayAdd),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l.holidayNameLabel,
            hintText: l.holidayNameHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  // ── Create from a calendar entry ───────────────────────────────────────────

  /// Reads the phone's calendar and lets the user turn one of its all-day
  /// entries into a holiday. Nothing is written until they confirm the range,
  /// so a mis-read event costs a tap, not a falsified week of reports.
  Future<void> _addFromCalendar() async {
    final l = AppLocalizations.of(context)!;
    final calendar = CalendarService();

    if (!await calendar.requestPermission()) {
      if (!mounted) return;
      _snack(l.holidayCalendarDenied);
      return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    List<CalendarEvent> events;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      events = await calendar.allDayEvents(
        // Back far enough to log a holiday after coming home, forward far
        // enough for next year's already-booked trip.
        start: DateTime(today.year, today.month - 3, today.day),
        end: DateTime(today.year + 1, today.month, today.day),
      );
    } catch (e) {
      appLogger.e('❌ Failed to read calendar: $e');
      events = const [];
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (events.isEmpty) {
      _snack(l.holidayCalendarEmpty);
      return;
    }

    final picked = await _pickCalendarEvent(events);
    if (picked == null || !mounted) return;
    await _addHoliday(seed: picked);
  }

  Future<CalendarEvent?> _pickCalendarEvent(List<CalendarEvent> events) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    return showModalBottomSheet<CalendarEvent>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l.holidayCalendarTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.holidayCalendarHint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: events.length,
                itemBuilder: (ctx, i) {
                  final e = events[i];
                  final subtitle = StringBuffer(
                      _formatDateRange(e.start, e.end, locale))
                    ..write(' · ')
                    ..write(l.holidayDays(e.dayCount));
                  if (e.calendarName != null && e.calendarName!.isNotEmpty) {
                    subtitle.write(' · ${e.calendarName}');
                  }
                  return ListTile(
                    leading: const Icon(Icons.event, color: Colors.orange),
                    title: Text(e.title),
                    subtitle: Text(subtitle.toString()),
                    onTap: () => Navigator.of(ctx).pop(e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rename / delete ────────────────────────────────────────────────────────

  Future<void> _rename(Holiday holiday) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: holiday.label ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.holidayRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l.holidayNameLabel,
            hintText: l.holidayNameHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final label = result.isEmpty ? null : result;
      await _service.renameHoliday(holiday.id, label);
      try {
        await LocalDataService.instance.renameHoliday(holiday.id, label);
      } catch (e) {
        appLogger.w('⚠️ Could not mirror holiday rename locally: $e');
      }
      await _load();
    } catch (e) {
      appLogger.e('❌ Failed to rename holiday: $e');
      _snack(l.holidaySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Holiday holiday) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.holidayDeleteTitle),
        content: Text(l.holidayDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.deleteHoliday(holiday.id);
      try {
        await LocalDataService.instance.deleteHoliday(holiday.id);
      } catch (e) {
        appLogger.w('⚠️ Could not mirror holiday deletion locally: $e');
      }
      _snack(l.holidayDeleted);
      await _load();
    } catch (e) {
      appLogger.e('❌ Failed to delete holiday: $e');
      _snack(l.holidaySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.holidaysTitle),
        actions: [
          if (CalendarService.isSupported)
            IconButton(
              icon: const Icon(Icons.event_available),
              tooltip: l.holidayFromCalendar,
              onPressed: _busy ? null : _addFromCalendar,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _addHoliday(),
        icon: const Icon(Icons.add),
        label: Text(l.holidayAdd),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _holidays.isEmpty
              ? _buildEmpty(l)
              : _buildList(l),
    );
  }

  Widget _buildEmpty(AppLocalizations l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏖️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              l.holidaysEmpty,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.holidaysEmptyHint,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            // Repeated from the app bar: the empty state is where someone who
            // has never declared a holiday actually looks.
            if (CalendarService.isSupported) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _busy ? null : _addFromCalendar,
                icon: const Icon(Icons.event_available),
                label: Text(l.holidayFromCalendar),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations l) {
    final current = _holidays.where((h) => h.isCurrent).toList();
    final upcoming = _holidays.where((h) => h.isUpcoming).toList();
    final past = _holidays.where((h) => h.isPast).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          // Upcoming ascending: the next holiday should be at the top of its
          // section, whereas past ones read best newest-first.
          if (current.isNotEmpty) ...[
            _sectionHeader(l.holidaySectionCurrent),
            ...current.map((h) => _tile(l, h, highlight: true)),
          ],
          if (upcoming.isNotEmpty) ...[
            _sectionHeader(l.holidaySectionUpcoming),
            ...(upcoming.reversed).map((h) => _tile(l, h)),
          ],
          if (past.isNotEmpty) ...[
            _sectionHeader(l.holidaySectionPast),
            ...past.map((h) => _tile(l, h, dimmed: true)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.grey.shade600,
          ),
        ),
      );

  Widget _tile(AppLocalizations l, Holiday h,
      {bool highlight = false, bool dimmed = false}) {
    final locale = Localizations.localeOf(context).toString();
    final subtitle = StringBuffer(_formatDateRange(h.start, h.end, locale))
      ..write(' · ')
      ..write(l.holidayDays(h.dayCount));
    if (h.hasGaps) subtitle.write(' · ${l.holidayHasGaps}');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: highlight ? Colors.orange.shade50 : null,
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.orange.shade300),
            )
          : null,
      child: Opacity(
        opacity: dimmed ? 0.6 : 1,
        child: ListTile(
          leading: Text(
            highlight ? '🎉' : '🏖️',
            style: const TextStyle(fontSize: 24),
          ),
          title: Text(
            h.label ?? l.holidayUnnamed,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle.toString()),
          onTap: _busy ? null : () => _rename(h),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            tooltip: l.delete,
            onPressed: _busy ? null : () => _delete(h),
          ),
        ),
      ),
    );
  }

  /// "10.–17. Aug 2026", collapsing the parts both ends share.
  String _formatDateRange(DateTime start, DateTime end, String locale) {
    if (start == end) {
      return DateFormat.yMMMd(locale).format(start);
    }
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat.d(locale).format(start)}.–'
          '${DateFormat.yMMMd(locale).format(end)}';
    }
    if (start.year == end.year) {
      return '${DateFormat.MMMd(locale).format(start)} – '
          '${DateFormat.yMMMd(locale).format(end)}';
    }
    return '${DateFormat.yMMMd(locale).format(start)} – '
        '${DateFormat.yMMMd(locale).format(end)}';
  }
}
