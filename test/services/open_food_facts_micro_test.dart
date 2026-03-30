import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/open_food_facts_service.dart';
import 'package:dietry/models/food_search_result.dart';

void main() {
  group('OpenFoodFactsService', () {
    late OpenFoodFactsService service;

    setUp(() => service = OpenFoodFactsService());

    group('Eingabevalidierung', () {
      test('searchByName — leerer Query gibt leere Liste zurück', () async {
        expect(await service.searchByName(''), isEmpty);
      });

      test('searchByName — Whitespace-only Query gibt leere Liste zurück',
          () async {
        expect(await service.searchByName('   '), isEmpty);
      });

      test('searchByBarcode — leerer Barcode gibt null zurück', () async {
        expect(await service.searchByBarcode(''), isNull);
      });

      test('searchByBarcode — Whitespace-only Barcode gibt null zurück',
          () async {
        expect(await service.searchByBarcode('  '), isNull);
      });
    });

    group('Rückgabetypen', () {
      // Prüft nur den Typ — ohne Netzwerkzugriff über die leere Eingabe
      test('searchByName gibt List<FoodSearchResult> zurück', () async {
        final result = await service.searchByName('');
        expect(result, isA<List<FoodSearchResult>>());
      });

      test('searchByBarcode gibt FoodSearchResult? zurück', () async {
        final result = await service.searchByBarcode('');
        expect(result, isNull); // null ist gültiger FoodSearchResult?
      });
    });
  });

  // Einheitenkonvertierung — exakte Spiegelung der Produktionslogik in
  // OpenFoodFactsService._convertUnit (private static method).
  // Diese Tests dokumentieren die erwartete Konvertierungstabelle.
  group('Einheitenkonvertierung (dokumentiert)', () {
    // Repliziert OpenFoodFactsService._convertUnit
    double? convert(double v, String from, String to) {
      if (from == to || from.isEmpty) return v;
      if (from == 'g' && to == 'mg') return v * 1000;
      if (from == 'g' && to == 'mcg') return v * 1000000;
      if (from == 'mg' && to == 'g') return v / 1000;
      if (from == 'mg' && to == 'mcg') return v * 1000;
      if (from == 'mcg' && to == 'g') return v / 1000000;
      if (from == 'mcg' && to == 'mg') return v / 1000;
      return null;
    }

    test('g → mg: 1 g = 1000 mg', () {
      expect(convert(1.0, 'g', 'mg'), 1000.0);
    });

    test('g → mcg: 1 g = 1 000 000 µg', () {
      expect(convert(1.0, 'g', 'mcg'), 1000000.0);
    });

    test('mg → mcg: 1 mg = 1000 µg', () {
      expect(convert(1.0, 'mg', 'mcg'), 1000.0);
    });

    test('mg → g: 1000 mg = 1 g', () {
      expect(convert(1000.0, 'mg', 'g'), 1.0);
    });

    test('mcg → mg: 1000 µg = 1 mg', () {
      expect(convert(1000.0, 'mcg', 'mg'), 1.0);
    });

    test('mcg → g: 1 000 000 µg = 1 g', () {
      expect(convert(1000000.0, 'mcg', 'g'), 1.0);
    });

    test('gleiche Einheit — kein Umrechnen', () {
      expect(convert(42.0, 'mg', 'mg'), 42.0);
      expect(convert(5.0, 'g', 'g'), 5.0);
      expect(convert(3.0, 'mcg', 'mcg'), 3.0);
    });

    test('leere from-Einheit — Wert unverändert', () {
      expect(convert(7.5, '', 'mg'), 7.5);
    });

    test('IU-Einheit — nicht konvertierbar (null)', () {
      expect(convert(100.0, 'iu', 'mcg'), isNull);
      expect(convert(100.0, 'IU', 'mg'), isNull);
    });

    group('Praxisbeispiele (OFF-Werte → DB-Zieleinheiten)', () {
      // Vitamin A: OFF liefert oft µg, Ziel = mcg (gleich)
      test('Vitamin A: µg → mcg (gleiche Einheit)', () {
        expect(convert(900.0, 'mcg', 'mcg'), 900.0);
      });

      // Calcium: OFF liefert mg, Ziel = mg
      test('Calcium: mg → mg (gleiche Einheit)', () {
        expect(convert(120.0, 'mg', 'mg'), 120.0);
      });

      // Calcium als g: 0.12 g → 120 mg
      test('Calcium: g → mg', () {
        expect(convert(0.12, 'g', 'mg'), closeTo(120.0, 1e-9));
      });

      // Vitamin B12: OFF liefert µg → Ziel mcg
      test('Vitamin B12: µg → mcg', () {
        expect(convert(2.4, 'mcg', 'mcg'), 2.4);
      });

      // Selen: OFF liefert µg → Ziel mcg
      test('Selen: µg → mcg (gleiche Einheit)', () {
        expect(convert(55.0, 'mcg', 'mcg'), 55.0);
      });

      // Gesättigte Fettsäuren: g → g
      test('Gesättigte Fettsäuren: g → g', () {
        expect(convert(3.5, 'g', 'g'), 3.5);
      });
    });
  });
}
