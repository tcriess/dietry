import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/gear.dart';
import 'package:dietry/services/reports_service.dart';

/// The gear card on the reports page answers two questions at once — "what did
/// I train on in this period" (the range, aggregated from raw activity rows)
/// and "when do I replace this" (the lifetime, which comes from the server and
/// includes distance the item had before tracking began). Mixing the two up
/// would silently mis-report wear, so the assembly is pinned down here.

Gear _gear(
  String id,
  String name, {
  bool retired = false,
  double? retireAtKm,
  GearCategory category = GearCategory.shoes,
}) =>
    Gear(
      id: id,
      name: name,
      category: category,
      retired: retired,
      retireAtKm: retireAtKm,
    );

Map<String, dynamic> _row(String? gearId, {num? km, num? minutes}) => {
      'gear_id': gearId,
      'distance_km': km,
      'duration_minutes': minutes,
    };

List<String> _names(List<GearReportItem> items) =>
    items.map((i) => i.gear.name).toList();

void main() {
  group('buildGearReport / range aggregation', () {
    test('sums distance and duration, and counts the activities', () {
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus')],
        lifetime: {},
        activityRows: [
          _row('a', km: 10.5, minutes: 55),
          _row('a', km: 7.25, minutes: 40),
          _row('a', km: 2.25, minutes: 15),
        ],
      );

      expect(items, hasLength(1));
      expect(items.single.rangeKm, closeTo(20.0, 1e-9));
      expect(items.single.rangeMinutes, 110);
      expect(items.single.rangeCount, 3);
      expect(items.single.usedInRange, isTrue);
    });

    test('a distance-less activity still counts as a use', () {
      // Gym sessions carry no distance_km. Dropping them would under-report the
      // activity count for anything that is not a shoe or a bike.
      final items = buildGearReport(
        gear: [_gear('a', 'Rowing machine', category: GearCategory.other)],
        lifetime: {},
        activityRows: [
          _row('a', km: null, minutes: 45),
          _row('a', km: null, minutes: 30),
        ],
      );

      expect(items.single.rangeKm, 0);
      expect(items.single.rangeMinutes, 75);
      expect(items.single.rangeCount, 2);
      expect(items.single.usedInRange, isTrue);
    });

    test('activities without gear are ignored', () {
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus')],
        lifetime: {},
        activityRows: [
          _row('a', km: 5, minutes: 30),
          _row(null, km: 100, minutes: 300),
        ],
      );

      expect(items.single.rangeKm, 5);
      expect(items.single.rangeCount, 1);
    });

    test('activities of gear the user no longer owns are ignored', () {
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus')],
        lifetime: {},
        activityRows: [_row('deleted-gear', km: 100, minutes: 300)],
      );

      expect(items.single.rangeCount, 0);
    });

    test('unused gear is still listed, with a zeroed range', () {
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus')],
        lifetime: {},
        activityRows: [],
      );

      expect(items, hasLength(1));
      expect(items.single.rangeCount, 0);
      expect(items.single.usedInRange, isFalse);
    });

    test('no gear yields no rows — the card is then hidden entirely', () {
      expect(
        buildGearReport(gear: [], lifetime: {}, activityRows: []),
        isEmpty,
      );
    });
  });

  group('buildGearReport / lifetime', () {
    test('lifetime is taken from the totals map, never from the range', () {
      // The whole point of the server-side RPC: the range only sees the rows
      // fetched for this period, while the lifetime spans the user's history
      // and includes the pre-tracking initial_distance_km.
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus', retireAtKm: 700)],
        lifetime: {
          'a': const GearTotals(
            gearId: 'a',
            totalDistanceKm: 480,
            totalMinutes: 3600,
            activityCount: 42,
          ),
        },
        activityRows: [_row('a', km: 12, minutes: 60)],
      );

      final item = items.single;
      expect(item.rangeKm, 12);
      expect(item.lifetime.totalDistanceKm, 480);
      expect(item.lifetime.activityCount, 42);
      expect(item.lifetime.wearFraction(item.gear.retireAtKm),
          closeTo(480 / 700, 1e-9));
    });

    test('gear missing from the totals map falls back to zeros', () {
      final items = buildGearReport(
        gear: [_gear('a', 'Pegasus')],
        lifetime: {},
        activityRows: [_row('a', km: 12, minutes: 60)],
      );

      expect(items.single.lifetime.gearId, 'a');
      expect(items.single.lifetime.totalDistanceKm, 0);
      expect(items.single.lifetime.wearFraction(null), isNull);
    });
  });

  group('buildGearReport / retired gear', () {
    test('retired and unused in the range is dropped', () {
      final items = buildGearReport(
        gear: [_gear('old', 'Worn-out Pegasus', retired: true)],
        lifetime: {},
        activityRows: [],
      );

      expect(items, isEmpty);
    });

    test('retired but used in the range is kept', () {
      // Retiring mid-period must not erase the kilometres already run on it.
      final items = buildGearReport(
        gear: [_gear('old', 'Worn-out Pegasus', retired: true)],
        lifetime: {},
        activityRows: [_row('old', km: 8, minutes: 45)],
      );

      expect(_names(items), ['Worn-out Pegasus']);
      expect(items.single.rangeKm, 8);
    });
  });

  group('buildGearReport / sort order', () {
    test('used gear comes before unused gear', () {
      final items = buildGearReport(
        gear: [
          _gear('idle', 'Untouched shoes'),
          _gear('used', 'Daily trainer'),
        ],
        lifetime: {},
        activityRows: [_row('used', km: 3, minutes: 20)],
      );

      expect(_names(items), ['Daily trainer', 'Untouched shoes']);
    });

    test('used beats unused even with nothing to rank it by', () {
      // The case the used-first rule exists for, and the only one where it is
      // load-bearing: an activity that recorded neither distance nor duration
      // ties an untouched item at zero on both, so without the rule the sort
      // would fall through to lifetime distance and put the shoes the user did
      // NOT train on this week first.
      final items = buildGearReport(
        gear: [
          _gear('idle', 'Untouched shoes'),
          _gear('used', 'Daily trainer'),
        ],
        lifetime: {
          'idle': const GearTotals(gearId: 'idle', totalDistanceKm: 900),
          'used': const GearTotals(gearId: 'used', totalDistanceKm: 20),
        },
        activityRows: [_row('used', km: null, minutes: null)],
      );

      expect(_names(items), ['Daily trainer', 'Untouched shoes']);
    });

    test('a distance-less but used item outranks untouched shoes', () {
      // The reason "used" is the primary key and not distance: a gym item logs
      // 0 km yet is the thing the user actually trained on.
      final items = buildGearReport(
        gear: [
          _gear('shoes', 'Untouched shoes'),
          _gear('gym', 'Rowing machine', category: GearCategory.other),
        ],
        lifetime: {
          // …and it outranks them even though they carry more lifetime distance.
          'shoes': const GearTotals(gearId: 'shoes', totalDistanceKm: 900),
        },
        activityRows: [_row('gym', km: null, minutes: 45)],
      );

      expect(_names(items), ['Rowing machine', 'Untouched shoes']);
    });

    test('used gear is ranked by range distance, descending', () {
      final items = buildGearReport(
        gear: [
          _gear('a', 'Shoes'),
          _gear('b', 'Bike', category: GearCategory.bike),
          _gear('c', 'Road shoes'),
        ],
        lifetime: {},
        activityRows: [
          _row('a', km: 82, minutes: 540),
          _row('b', km: 210, minutes: 660),
          _row('c', km: 14, minutes: 120),
        ],
      );

      expect(_names(items), ['Bike', 'Shoes', 'Road shoes']);
    });

    test('equal distance falls back to time, then to lifetime distance', () {
      final items = buildGearReport(
        gear: [
          _gear('low', 'Newer'),
          _gear('high', 'Older'),
          _gear('slow', 'Slowest'),
        ],
        lifetime: {
          'low': const GearTotals(gearId: 'low', totalDistanceKm: 100),
          'high': const GearTotals(gearId: 'high', totalDistanceKm: 900),
        },
        activityRows: [
          // Same distance, more time on it → ranked above both.
          _row('slow', km: 10, minutes: 95),
          // Same distance and time → the more worn item wins.
          _row('low', km: 10, minutes: 60),
          _row('high', km: 10, minutes: 60),
        ],
      );

      expect(_names(items), ['Slowest', 'Older', 'Newer']);
    });
  });
}
