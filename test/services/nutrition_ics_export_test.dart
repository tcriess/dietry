import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/nutrition_ics_export.dart';
import 'package:dietry/services/reports_service.dart' show DailyNutritionData;

const _labels = NutritionIcsLabels(
  calendarName: 'Dietry — Nutrition',
  calories: 'Calories',
  protein: 'Protein',
  fat: 'Fat',
  carbs: 'Carbs',
);

DailyNutritionData _day(
  String date, {
  double calories = 1850,
  double protein = 95,
  double fat = 60,
  double carbs = 210,
}) =>
    DailyNutritionData(
      date: DateTime.parse(date),
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
    );

String _ics(List<DailyNutritionData> days, {NutritionIcsLabels? labels}) =>
    buildNutritionIcs(
      days: days,
      labels: labels ?? _labels,
      generatedAt: DateTime.utc(2026, 8, 7, 9, 30, 15),
    );

void main() {
  group('calendar envelope', () {
    test('wraps the events in a VCALENDAR with CRLF line endings', () {
      final ics = _ics([_day('2026-08-05')]);
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, contains('VERSION:2.0'));
      // A bare LF anywhere would make strict parsers reject the file.
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('stamps every event with the generation time in UTC', () {
      expect(_ics([_day('2026-08-05')]), contains('DTSTAMP:20260807T093015Z'));
    });
  });

  group('event dates', () {
    test('DTEND is the day after DTSTART, since all-day ends are exclusive', () {
      final ics = _ics([_day('2026-08-05')]);
      expect(ics, contains('DTSTART;VALUE=DATE:20260805'));
      expect(ics, contains('DTEND;VALUE=DATE:20260806'));
    });

    test('rolls over month and year boundaries', () {
      final ics = _ics([_day('2026-12-31')]);
      expect(ics, contains('DTSTART;VALUE=DATE:20261231'));
      expect(ics, contains('DTEND;VALUE=DATE:20270101'));
    });

    test('pads single-digit months and days', () {
      expect(_ics([_day('2026-01-02')]),
          contains('DTSTART;VALUE=DATE:20260102'));
    });
  });

  group('event content', () {
    test('the summary leads with calories', () {
      expect(_ics([_day('2026-08-05', calories: 1849.6)]),
          contains('SUMMARY:1850 kcal'));
    });

    test('falls back to protein when calories are not tracked', () {
      // Macro-only mode: the day has macros but no calorie total.
      final ics = _ics([_day('2026-08-05', calories: 0)]);
      expect(ics, contains('SUMMARY:Protein 95 g'));
    });

    test('the description carries the full breakdown on one folded line', () {
      final ics = _ics([_day('2026-08-05')]);
      expect(
        ics,
        contains('DESCRIPTION:Calories: 1850 kcal\\nProtein: 95 g\\n'
            'Fat: 60 g\\nCarbs: 210 g'),
      );
    });

    test('marks days transparent so they do not show the user as busy', () {
      expect(_ics([_day('2026-08-05')]), contains('TRANSP:TRANSPARENT'));
    });
  });

  group('skipping empty days', () {
    test('a day with nothing logged produces no event', () {
      final ics = _ics([
        _day('2026-08-05', calories: 0, protein: 0, fat: 0, carbs: 0),
      ]);
      expect(ics, isNot(contains('BEGIN:VEVENT')));
    });

    test('keeps days that have macros but no calories', () {
      final ics = _ics([
        _day('2026-08-05', calories: 0, fat: 0, carbs: 0),
      ]);
      expect(ics, contains('BEGIN:VEVENT'));
    });

    test('empty days do not interrupt the ones around them', () {
      final ics = _ics([
        _day('2026-08-04'),
        _day('2026-08-05', calories: 0, protein: 0, fat: 0, carbs: 0),
        _day('2026-08-06'),
      ]);
      expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
      expect(ics, contains('DTSTART;VALUE=DATE:20260804'));
      expect(ics, isNot(contains('DTSTART;VALUE=DATE:20260805')));
      expect(ics, contains('DTSTART;VALUE=DATE:20260806'));
    });
  });

  group('UID stability', () {
    test('the same day always gets the same UID, so re-import updates', () {
      final first = _ics([_day('2026-08-05')]);
      final second = buildNutritionIcs(
        days: [_day('2026-08-05', calories: 2000)],
        labels: _labels,
        // A later export of the same day must not mint a new UID.
        generatedAt: DateTime.utc(2027, 1, 1),
      );
      expect(first, contains('UID:dietry-nutrition-20260805@dietry.de'));
      expect(second, contains('UID:dietry-nutrition-20260805@dietry.de'));
    });

    test('different days get different UIDs', () {
      final ics = _ics([_day('2026-08-05'), _day('2026-08-06')]);
      expect(ics, contains('UID:dietry-nutrition-20260805@dietry.de'));
      expect(ics, contains('UID:dietry-nutrition-20260806@dietry.de'));
    });
  });

  group('RFC 5545 text rules', () {
    test('escapes the characters that carry structural meaning', () {
      final ics = _ics(
        [_day('2026-08-05')],
        labels: const NutritionIcsLabels(
          calendarName: r'Diet; rest, and\break',
          calories: 'Calories',
          protein: 'Protein',
          fat: 'Fat',
          carbs: 'Carbs',
        ),
      );
      expect(ics, contains(r'X-WR-CALNAME:Diet\; rest\, and\\break'));
    });

    test('folds content lines to 75 octets', () {
      final ics = _ics(
        [_day('2026-08-05')],
        labels: NutritionIcsLabels(
          calendarName: 'N' * 200,
          calories: 'Calories',
          protein: 'Protein',
          fat: 'Fat',
          carbs: 'Carbs',
        ),
      );
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75),
            reason: 'line exceeds the 75-octet limit: $line');
      }
    });

    test('continuation lines start with a single space', () {
      final ics = _ics(
        [_day('2026-08-05')],
        labels: NutritionIcsLabels(
          calendarName: 'N' * 200,
          calories: 'Calories',
          protein: 'Protein',
          fat: 'Fat',
          carbs: 'Carbs',
        ),
      );
      final lines = ics.split('\r\n');
      final folded = lines.where((l) => l.startsWith(' ')).toList();
      expect(folded, isNotEmpty);
      // Unfolding must give the name back exactly — no character eaten, none
      // duplicated at the seam.
      final unfolded = ics.replaceAll('\r\n ', '');
      expect(unfolded, contains('X-WR-CALNAME:${'N' * 200}'));
    });

    test('never splits a multi-byte character across a fold', () {
      final ics = _ics(
        [_day('2026-08-05')],
        labels: NutritionIcsLabels(
          // 200 three-byte characters: a naive byte-slice would cut one apart.
          calendarName: '　' * 200,
          calories: 'Calories',
          protein: 'Protein',
          fat: 'Fat',
          carbs: 'Carbs',
        ),
      );
      // Round-tripping through UTF-8 proves no code unit was mangled.
      expect(utf8.decode(utf8.encode(ics)), ics);
      expect(ics.replaceAll('\r\n ', ''), contains('　' * 200));
    });
  });
}
