import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/gear.dart';
import 'package:dietry/models/physical_activity.dart';

void main() {
  group('Gear JSON', () {
    test('toJson emits clearable fields even when null', () {
      // updateGear PATCHes the full row: if these were omitted when null, a
      // user could never remove a wear budget or an auto-attach type.
      final json = const Gear(name: 'Pegasus 41').toJson();

      expect(json.containsKey('default_activity_type'), isTrue);
      expect(json['default_activity_type'], isNull);
      expect(json.containsKey('retire_at_km'), isTrue);
      expect(json['retire_at_km'], isNull);
      expect(json.containsKey('notes'), isTrue);
      expect(json['notes'], isNull);
    });

    test('toJson omits a null id so the DB default can fire', () {
      expect(const Gear(name: 'Pegasus 41').toJson().containsKey('id'), isFalse);
      expect(
        const Gear(id: 'abc', name: 'Pegasus 41').toJson()['id'],
        'abc',
      );
    });

    test('round-trips through JSON', () {
      const gear = Gear(
        id: 'g1',
        name: 'Pegasus 41',
        category: GearCategory.shoes,
        defaultActivityType: ActivityType.running,
        initialDistanceKm: 120.5,
        retireAtKm: 800,
        retired: true,
        notes: 'blue ones',
      );

      final back = Gear.fromJson(gear.toJson());

      expect(back.id, 'g1');
      expect(back.name, 'Pegasus 41');
      expect(back.category, GearCategory.shoes);
      expect(back.defaultActivityType, ActivityType.running);
      expect(back.initialDistanceKm, 120.5);
      expect(back.retireAtKm, 800);
      expect(back.retired, isTrue);
      expect(back.notes, 'blue ones');
    });

    test('fromJson reads SQLite 0/1 as a bool', () {
      // The local mirror stores `retired` as an INTEGER — sqflite has no bool.
      expect(
        Gear.fromJson({'name': 'x', 'category': 'shoes', 'retired': 1}).retired,
        isTrue,
      );
      expect(
        Gear.fromJson({'name': 'x', 'category': 'shoes', 'retired': 0}).retired,
        isFalse,
      );
    });

    test('fromJson tolerates unknown category / activity type', () {
      final gear = Gear.fromJson({
        'name': 'x',
        'category': 'spaceship',
        'default_activity_type': 'quidditch',
      });
      expect(gear.category, GearCategory.other);
      expect(gear.defaultActivityType, ActivityType.other);
    });
  });

  group('GearTotals.wearFraction', () {
    const totals = GearTotals(gearId: 'g1', totalDistanceKm: 400);

    test('is null without a wear budget', () {
      expect(totals.wearFraction(null), isNull);
      expect(totals.wearFraction(0), isNull);
    });

    test('is the used fraction of the budget', () {
      expect(totals.wearFraction(800), 0.5);
    });

    test('goes past 1.0 once the budget is blown', () {
      expect(totals.wearFraction(200), 2.0);
    });
  });

  group('ActivityTypeExtension.fromDbActivityName', () {
    test('matches a listed candidate name', () {
      expect(
        ActivityTypeExtension.fromDbActivityName('Laufen (moderat)'),
        ActivityType.running,
      );
      expect(
        ActivityTypeExtension.fromDbActivityName('Radfahren (normal)'),
        ActivityType.cycling,
      );
    });

    test('matches the rest of a seeded family via the base name', () {
      // 'Laufen (schnell)' is in the seed but NOT in dbActivityCandidates —
      // stripping the intensity qualifier is what makes it resolve.
      expect(
        ActivityTypeExtension.fromDbActivityName('Laufen (schnell)'),
        ActivityType.running,
      );
      expect(
        ActivityTypeExtension.fromDbActivityName('Gehen (langsam)'),
        ActivityType.walking,
      );
      expect(
        ActivityTypeExtension.fromDbActivityName('Schwimmen (intensiv)'),
        ActivityType.swimming,
      );
      expect(
        ActivityTypeExtension.fromDbActivityName('Krafttraining (leicht)'),
        ActivityType.weightTraining,
      );
    });

    test('is case-insensitive and trims', () {
      expect(
        ActivityTypeExtension.fromDbActivityName('  rADFAHREN  '),
        ActivityType.cycling,
      );
    });

    test('matches localized candidates', () {
      expect(
        ActivityTypeExtension.fromDbActivityName('Running'),
        ActivityType.running,
      );
      expect(
        ActivityTypeExtension.fromDbActivityName('Ciclismo'),
        ActivityType.cycling,
      );
    });

    test('returns null for null or an unclaimed name', () {
      expect(ActivityTypeExtension.fromDbActivityName(null), isNull);
      expect(ActivityTypeExtension.fromDbActivityName('Sprinten'), isNull);
      expect(ActivityTypeExtension.fromDbActivityName('Kanufahren'), isNull);
    });
  });

  group('PhysicalActivity.gearId', () {
    PhysicalActivity build({String? gearId}) => PhysicalActivity(
          startTime: DateTime(2026, 7, 12, 8),
          endTime: DateTime(2026, 7, 12, 9),
          gearId: gearId,
        );

    test('toJson always emits gear_id so a PATCH can clear it', () {
      // Unlike the other nullable fields, which are omitted when null and so
      // can never be unset once written.
      final json = build().toJson();
      expect(json.containsKey('gear_id'), isTrue);
      expect(json['gear_id'], isNull);
    });

    test('round-trips through JSON', () {
      expect(PhysicalActivity.fromJson(build(gearId: 'g1').toJson()).gearId, 'g1');
    });

    test('copyWith keeps gearId, and clearGearId removes it', () {
      final a = build(gearId: 'g1');
      expect(a.copyWith(distanceKm: 10).gearId, 'g1');
      expect(a.copyWith(gearId: 'g2').gearId, 'g2');
      expect(a.copyWith(clearGearId: true).gearId, isNull);
    });
  });
}
