import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/utils/number_utils.dart';

void main() {
  group('parseDouble / tryParseDouble', () {
    test('parses comma decimal separator', () {
      expect(parseDouble('1,5'), 1.5);
      expect(tryParseDouble('2,25'), 2.25);
    });

    test('tryParseDouble returns null for empty/invalid', () {
      expect(tryParseDouble(null), isNull);
      expect(tryParseDouble(''), isNull);
      expect(tryParseDouble('abc'), isNull);
    });
  });

  group('formatAmount', () {
    test('whole numbers have no decimals', () {
      expect(formatAmount(2.0), '2');
      expect(formatAmount(100.0), '100');
    });

    test('fractional values keep one decimal', () {
      expect(formatAmount(1.5), '1.5');
      expect(formatAmount(2.5), '2.5');
      expect(formatAmount(0.5), '0.5');
    });
  });

  group('scaleToTotal / toPer100g round trip', () {
    test('per-100g scaled to total for grams', () {
      expect(scaleToTotal(250, 200), 500); // 250 kcal/100g × 200g
      expect(scaleToTotal(5, 60), closeTo(3.0, 1e-9)); // 5g/100g × 60g
    });

    test('total converted back to per-100g', () {
      expect(toPer100g(500, 200), 250);
      expect(toPer100g(3, 60), closeTo(5.0, 1e-9));
    });

    test('toPer100g guards against non-positive grams', () {
      expect(toPer100g(100, 0), 0);
      expect(toPer100g(100, -10), 0);
    });

    test('round trip is stable for arbitrary grams', () {
      for (final grams in [37.0, 120.0, 250.0, 12.5]) {
        const per100 = 7.3;
        final total = scaleToTotal(per100, grams);
        expect(toPer100g(total, grams), closeTo(per100, 1e-9));
      }
    });
  });
}
