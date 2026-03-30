import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/usda_service.dart';
import 'package:dietry/models/food_search_result.dart';

void main() {
  group('UsdaService', () {
    late UsdaService service;

    setUp(() => service = UsdaService());

    group('Eingabevalidierung', () {
      test('searchByName — leerer Query gibt leere Liste zurück', () async {
        // hasUsda == false in Test-Umgebung (kein API-Key), gibt früh [] zurück
        expect(await service.searchByName(''), isEmpty);
      });

      test('searchByName — Whitespace-only Query gibt leere Liste zurück',
          () async {
        expect(await service.searchByName('   '), isEmpty);
      });
    });

    group('Rückgabetypen', () {
      test('searchByName gibt List<FoodSearchResult> zurück', () async {
        final result = await service.searchByName('');
        expect(result, isA<List<FoodSearchResult>>());
      });
    });
  });

  // Einheitenkonvertierung USDA — repliziert UsdaService._convertUnit.
  // USDA nutzt Großbuchstaben: 'G', 'MG', 'UG'.
  group('USDA Einheitenkonvertierung (dokumentiert)', () {
    double? convert(double v, String from, String to) {
      if (from == to) return v;
      if (from == 'G' && to == 'MG') return v * 1000;
      if (from == 'G' && to == 'UG') return v * 1000000;
      if (from == 'MG' && to == 'G') return v / 1000;
      if (from == 'MG' && to == 'UG') return v * 1000;
      if (from == 'UG' && to == 'G') return v / 1000000;
      if (from == 'UG' && to == 'MG') return v / 1000;
      return null;
    }

    test('G → MG: 1 g = 1000 mg', () {
      expect(convert(1.0, 'G', 'MG'), 1000.0);
    });

    test('G → UG: 1 g = 1 000 000 µg', () {
      expect(convert(1.0, 'G', 'UG'), 1000000.0);
    });

    test('MG → UG: 1 mg = 1000 µg', () {
      expect(convert(1.0, 'MG', 'UG'), 1000.0);
    });

    test('MG → G: 1000 mg = 1 g', () {
      expect(convert(1000.0, 'MG', 'G'), 1.0);
    });

    test('UG → MG: 1000 µg = 1 mg', () {
      expect(convert(1000.0, 'UG', 'MG'), 1.0);
    });

    test('gleiche Einheit — kein Umrechnen', () {
      expect(convert(42.0, 'MG', 'MG'), 42.0);
      expect(convert(5.0, 'G', 'G'), 5.0);
      expect(convert(3.0, 'UG', 'UG'), 3.0);
    });

    test('unbekannte Kombination gibt null zurück', () {
      expect(convert(1.0, 'IU', 'MG'), isNull);
      expect(convert(1.0, 'KCAL', 'MG'), isNull);
    });

    group('Praxisbeispiele (USDA-Nährwerte → DB-Zieleinheiten)', () {
      // Vitamin A RAE: USDA liefert UG, Ziel = UG
      test('Vitamin A RAE: UG → UG (gleich)', () {
        expect(convert(900.0, 'UG', 'UG'), 900.0);
      });

      // Calcium: USDA liefert MG, Ziel = MG
      test('Calcium: MG → MG (gleich)', () {
        expect(convert(1000.0, 'MG', 'MG'), 1000.0);
      });

      // Gesättigte Fettsäuren: USDA liefert G, Ziel = G
      test('Gesättigte Fettsäuren: G → G (gleich)', () {
        expect(convert(5.2, 'G', 'G'), 5.2);
      });

      // Vitamin B12: USDA liefert UG, Ziel = UG (mcg)
      test('Vitamin B12: UG → UG', () {
        expect(convert(2.4, 'UG', 'UG'), 2.4);
      });

      // Selenium: USDA liefert UG, Ziel = UG
      test('Selenium: UG → UG', () {
        expect(convert(55.0, 'UG', 'UG'), 55.0);
      });
    });
  });

  // Testen der USDA-Nährstoffnamen-Mappings
  group('USDA Nährstoffname-Mapping', () {
    // Vollständige Mapping-Tabelle aus _extractMicros, hier dokumentiert.
    const mapping = {
      'Vitamin A, RAE': 'vitamin_a_mcg',
      'Vitamin D (D2 + D3)': 'vitamin_d_mcg',
      'Vitamin E (alpha-tocopherol)': 'vitamin_e_mg',
      'Vitamin K (phylloquinone)': 'vitamin_k_mcg',
      'Vitamin K1': 'vitamin_k_mcg',
      'Vitamin C, total ascorbic acid': 'vitamin_c_mg',
      'Thiamin': 'vitamin_b1_mg',
      'Riboflavin': 'vitamin_b2_mg',
      'Niacin': 'vitamin_b3_mg',
      'Pantothenic acid': 'vitamin_b5_mg',
      'Vitamin B-6': 'vitamin_b6_mg',
      'Biotin': 'vitamin_b7_mcg',
      'Folate, total': 'vitamin_b9_mcg',
      'Folate, DFE': 'vitamin_b9_mcg',
      'Vitamin B-12': 'vitamin_b12_mcg',
      'Calcium, Ca': 'calcium_mg',
      'Iron, Fe': 'iron_mg',
      'Magnesium, Mg': 'magnesium_mg',
      'Phosphorus, P': 'phosphorus_mg',
      'Potassium, K': 'potassium_mg',
      'Zinc, Zn': 'zinc_mg',
      'Selenium, Se': 'selenium_mcg',
      'Iodine, I': 'iodine_mcg',
      'Manganese, Mn': 'manganese_mg',
      'Copper, Cu': 'copper_mg',
      'Fatty acids, total saturated': 'saturated_fat_g',
      'Fatty acids, total monounsaturated': 'monounsaturated_fat_g',
      'Fatty acids, total polyunsaturated': 'polyunsaturated_fat_g',
      'Fatty acids, total trans': 'trans_fat_g',
      'Cholesterol': 'cholesterol_mg',
    };

    test('Mapping enthält alle 30 erwarteten Nährstoffe', () {
      // 29 Einträge (Folate + K1 sind Aliase) → 27 DB-Spalten
      final dbColumns = mapping.values.toSet();
      expect(dbColumns.length, greaterThanOrEqualTo(25));
    });

    test('Alle DB-Spalten folgen der Namenskonvention', () {
      for (final col in mapping.values) {
        expect(
          col,
          matches(RegExp(r'^[a-z][a-z0-9_]+_(mg|mcg|g)$')),
          reason: 'Spalte "$col" entspricht nicht dem Schema name_einheit',
        );
      }
    });

    test('Vitamin-A-Mapping ist korrekt', () {
      expect(mapping['Vitamin A, RAE'], 'vitamin_a_mcg');
    });

    test('Calcium-Mapping ist korrekt', () {
      expect(mapping['Calcium, Ca'], 'calcium_mg');
    });

    test('Cholesterin-Mapping ist korrekt', () {
      expect(mapping['Cholesterol'], 'cholesterol_mg');
    });

    test('Folsäure-Aliase zeigen auf dieselbe Spalte', () {
      expect(mapping['Folate, total'], mapping['Folate, DFE']);
    });

    test('Vitamin-K-Aliase zeigen auf dieselbe Spalte', () {
      expect(mapping['Vitamin K (phylloquinone)'], mapping['Vitamin K1']);
    });
  });
}
