import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/cheat_day.dart';
import 'package:dietry/models/holiday.dart';

CheatDay _day(String date, {String? holidayId, String? note}) => CheatDay(
      id: 'id-$date',
      userId: 'u1',
      cheatDate: DateTime.parse(date),
      note: note,
      holidayId: holidayId,
      createdAt: DateTime(2026),
    );

void main() {
  group('CheatDay.fromJson', () {
    test('reads holiday_id and tolerates its absence', () {
      final withHoliday = CheatDay.fromJson({
        'id': 'a',
        'user_id': 'u1',
        'cheat_date': '2026-08-10',
        'note': 'Sommerurlaub',
        'holiday_id': 'h1',
        'created_at': '2026-08-01T10:00:00Z',
      });
      expect(withHoliday.holidayId, 'h1');
      expect(withHoliday.note, 'Sommerurlaub');

      final handToggled = CheatDay.fromJson({
        'id': 'b',
        'user_id': 'u1',
        'cheat_date': '2026-08-10',
        'created_at': '2026-08-01T10:00:00Z',
      });
      expect(handToggled.holidayId, isNull);
    });

    test('toJson omits holiday_id when there is none', () {
      expect(_day('2026-08-10').toJson().containsKey('holiday_id'), isFalse);
      expect(_day('2026-08-10', holidayId: 'h1').toJson()['holiday_id'], 'h1');
    });
  });

  // Drives the overview banner: it names the holiday instead of the generic
  // cheat-day text, but only for a day that really belongs to a named one.
  group('CheatDay.holidayLabel', () {
    test('names the holiday for one of its days', () {
      expect(
        _day('2026-08-10', holidayId: 'h1', note: 'Sommerurlaub').holidayLabel,
        'Sommerurlaub',
      );
    });

    test('a hand-toggled day has no label even if it carries a note', () {
      expect(_day('2026-08-10', note: 'zu viel Pizza').holidayLabel, isNull);
    });

    test('an unnamed holiday has no label', () {
      expect(_day('2026-08-10', holidayId: 'h1').holidayLabel, isNull);
      expect(_day('2026-08-10', holidayId: 'h1', note: '').holidayLabel, isNull);
    });

    test('a plain cheat day has no label', () {
      expect(_day('2026-08-10').holidayLabel, isNull);
    });
  });

  group('Holiday.groupFrom', () {
    test('ignores hand-toggled days that belong to no holiday', () {
      final holidays = Holiday.groupFrom([
        _day('2026-08-10'),
        _day('2026-08-11'),
      ]);
      expect(holidays, isEmpty);
    });

    test('folds days of one holiday into a single entry', () {
      final holidays = Holiday.groupFrom([
        _day('2026-08-12', holidayId: 'h1', note: 'Sommerurlaub'),
        _day('2026-08-10', holidayId: 'h1', note: 'Sommerurlaub'),
        _day('2026-08-11', holidayId: 'h1', note: 'Sommerurlaub'),
      ]);

      expect(holidays, hasLength(1));
      final h = holidays.single;
      expect(h.id, 'h1');
      expect(h.label, 'Sommerurlaub');
      expect(h.start, DateTime(2026, 8, 10));
      expect(h.end, DateTime(2026, 8, 12));
      expect(h.dayCount, 3);
      expect(h.spanDays, 3);
      expect(h.hasGaps, isFalse);
    });

    test('separates two holidays and sorts them newest first', () {
      final holidays = Holiday.groupFrom([
        _day('2026-08-10', holidayId: 'h1'),
        _day('2026-12-24', holidayId: 'h2'),
        _day('2026-12-25', holidayId: 'h2'),
      ]);
      expect(holidays.map((h) => h.id), ['h2', 'h1']);
      expect(holidays.first.dayCount, 2);
    });

    test('a day un-cheated inside the range shows up as a gap', () {
      // 10th and 12th remain; the 11th was toggled off individually.
      final holidays = Holiday.groupFrom([
        _day('2026-08-10', holidayId: 'h1'),
        _day('2026-08-12', holidayId: 'h1'),
      ]);
      final h = holidays.single;
      expect(h.dayCount, 2);
      expect(h.spanDays, 3);
      expect(h.hasGaps, isTrue);
    });

    test('label falls back to the first non-empty note', () {
      final holidays = Holiday.groupFrom([
        _day('2026-08-10', holidayId: 'h1', note: null),
        _day('2026-08-11', holidayId: 'h1', note: 'Urlaub'),
      ]);
      expect(holidays.single.label, 'Urlaub');
    });

    test('an unnamed holiday has a null label', () {
      final holidays = Holiday.groupFrom([
        _day('2026-08-10', holidayId: 'h1'),
      ]);
      expect(holidays.single.label, isNull);
    });
  });

  group('Holiday time classification', () {
    final today = DateTime.now();
    DateTime shift(int days) => today.add(Duration(days: days));

    Holiday build(int startOffset, int endOffset) => Holiday(
          id: 'h',
          start: DateTime(
              shift(startOffset).year,
              shift(startOffset).month,
              shift(startOffset).day),
          end: DateTime(
              shift(endOffset).year, shift(endOffset).month, shift(endOffset).day),
          dayCount: endOffset - startOffset + 1,
        );

    test('a range entirely in the future is upcoming', () {
      final h = build(5, 12);
      expect(h.isUpcoming, isTrue);
      expect(h.isCurrent, isFalse);
      expect(h.isPast, isFalse);
    });

    test('a range entirely in the past is past', () {
      final h = build(-12, -5);
      expect(h.isPast, isTrue);
      expect(h.isCurrent, isFalse);
      expect(h.isUpcoming, isFalse);
    });

    test('a range spanning today is current', () {
      final h = build(-2, 2);
      expect(h.isCurrent, isTrue);
      expect(h.isPast, isFalse);
      expect(h.isUpcoming, isFalse);
    });

    test('a holiday that starts today is current, not upcoming', () {
      final h = build(0, 3);
      expect(h.isCurrent, isTrue);
      expect(h.isUpcoming, isFalse);
    });

    test('a holiday that ends today is current, not past', () {
      final h = build(-3, 0);
      expect(h.isCurrent, isTrue);
      expect(h.isPast, isFalse);
    });
  });
}
