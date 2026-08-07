import 'dart:convert';

import 'reports_service.dart' show DailyNutritionData;

/// Localized field names for the event description. Passed in rather than
/// looked up here so the generator stays a pure function with no dependency on
/// a BuildContext, and can be unit-tested without a widget tree.
class NutritionIcsLabels {
  final String calendarName;
  final String calories;
  final String protein;
  final String fat;
  final String carbs;

  const NutritionIcsLabels({
    required this.calendarName,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });
}

/// Renders a day-per-event iCalendar file (RFC 5545) of logged nutrition, for
/// the user to import into whatever calendar app they use.
///
/// A one-shot file rather than a subscribable feed on purpose: a feed would
/// have to be an unauthenticated secret URL that the calendar provider fetches
/// and caches, i.e. health data permanently outside the user's control. See
/// docs/calendar_integration.md.
///
/// Days with nothing logged are skipped — a year of "0 kcal" entries would
/// bury the days that actually carry data.
String buildNutritionIcs({
  required List<DailyNutritionData> days,
  required NutritionIcsLabels labels,
  required DateTime generatedAt,
}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Dietry//Nutrition Export//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escape(labels.calendarName)}',
  ];

  final stamp = _formatUtcStamp(generatedAt);

  for (final day in days) {
    if (day.calories <= 0 &&
        day.protein <= 0 &&
        day.fat <= 0 &&
        day.carbs <= 0) {
      continue;
    }

    final date = _formatDate(day.date);
    final description = [
      '${labels.calories}: ${_num(day.calories)} kcal',
      '${labels.protein}: ${_num(day.protein)} g',
      '${labels.fat}: ${_num(day.fat)} g',
      '${labels.carbs}: ${_num(day.carbs)} g',
    ].join('\\n');

    lines.addAll([
      'BEGIN:VEVENT',
      // Stable across exports, so re-importing the same range updates the
      // existing entries instead of stacking a second copy on top of them.
      'UID:dietry-nutrition-$date@dietry.de',
      'DTSTAMP:$stamp',
      'DTSTART;VALUE=DATE:$date',
      // DTEND is EXCLUSIVE for all-day events (RFC 5545 §3.8.2.2): a one-day
      // entry ends on the following day. Emitting the same date here would
      // produce a zero-length event that several calendar apps drop silently.
      'DTEND;VALUE=DATE:${_formatDate(day.date.add(const Duration(days: 1)))}',
      'SUMMARY:${_escape(_summary(day, labels))}',
      'DESCRIPTION:$description',
      // Nutrition is a note about the day, not an appointment — it must not
      // make the user look busy to anyone sharing their calendar.
      'TRANSP:TRANSPARENT',
      'END:VEVENT',
    ]);
  }

  lines.add('END:VCALENDAR');

  // RFC 5545 mandates CRLF line endings.
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// What shows in a day cell, so it has to survive being truncated: the single
/// most-watched number first. Falls back to protein for macro-only users, who
/// track without calories at all.
String _summary(DailyNutritionData day, NutritionIcsLabels labels) {
  if (day.calories > 0) return '${_num(day.calories)} kcal';
  return '${labels.protein} ${_num(day.protein)} g';
}

String _num(double value) => value.round().toString();

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

String _formatUtcStamp(DateTime d) {
  final u = d.toUtc();
  return '${_formatDate(u)}T'
      '${u.hour.toString().padLeft(2, '0')}'
      '${u.minute.toString().padLeft(2, '0')}'
      '${u.second.toString().padLeft(2, '0')}Z';
}

/// Escapes the characters RFC 5545 §3.3.11 gives structural meaning to.
/// Backslash goes first, or it would double-escape the ones added after it.
String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');

/// Folds a content line to 75 octets, per RFC 5545 §3.1. Counting is in UTF-8
/// bytes rather than characters, and never splits one: a break inside a
/// multi-byte character would corrupt it. Continuation lines start with a
/// single space, which counts towards their own 75.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;

  final buffer = StringBuffer();
  var lineLength = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    final charLength = utf8.encode(char).length;
    if (lineLength + charLength > 75) {
      buffer.write('\r\n ');
      lineLength = 1; // the leading space
    }
    buffer.write(char);
    lineLength += charLength;
  }
  return buffer.toString();
}
