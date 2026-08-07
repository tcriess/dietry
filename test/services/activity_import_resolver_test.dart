import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/physical_activity.dart';
import 'package:dietry/services/activity_import_resolver.dart';

/// A stored row. Health-Connect-sourced unless [source] says otherwise.
PhysicalActivity _stored({
  required String id,
  String? hcId,
  ActivityType type = ActivityType.cycling,
  String start = '2026-08-07T10:00:00',
  String end = '2026-08-07T10:30:00',
  double? calories,
  double? distanceKm,
  String? gearId,
  String? notes,
  DataSource source = DataSource.healthConnect,
}) =>
    PhysicalActivity(
      id: id,
      activityType: type,
      startTime: DateTime.parse(start),
      endTime: DateTime.parse(end),
      caloriesBurned: calories,
      distanceKm: distanceKm,
      gearId: gearId,
      notes: notes,
      source: source,
      healthConnectRecordId: hcId,
    );

/// A record arriving from Health Connect: no id yet, always HC-sourced.
PhysicalActivity _incoming({
  required String hcId,
  ActivityType type = ActivityType.cycling,
  String start = '2026-08-07T10:00:00',
  String end = '2026-08-07T10:45:00',
  double? calories,
  double? distanceKm,
  int? steps,
  double? heartRate,
}) =>
    PhysicalActivity(
      activityType: type,
      startTime: DateTime.parse(start),
      endTime: DateTime.parse(end),
      caloriesBurned: calories,
      distanceKm: distanceKm,
      steps: steps,
      avgHeartRate: heartRate,
      source: DataSource.healthConnect,
      healthConnectRecordId: hcId,
    );

void main() {
  group('nothing stored yet', () {
    test('an unseen workout is created', () {
      final plan = resolveActivityImport(
        existing: const [],
        incoming: [_incoming(hcId: 'a')],
      );
      expect(plan.create, hasLength(1));
      expect(plan.update, isEmpty);
      expect(plan.delete, isEmpty);
    });

    test('creates are ordered chronologically', () {
      final plan = resolveActivityImport(
        existing: const [],
        incoming: [
          _incoming(
              hcId: 'late',
              start: '2026-08-07T18:00:00',
              end: '2026-08-07T18:30:00'),
          _incoming(
              hcId: 'early',
              start: '2026-08-07T07:00:00',
              end: '2026-08-07T07:30:00'),
        ],
      );
      expect(plan.create.map((a) => a.healthConnectRecordId),
          ['early', 'late']);
    });

    test('two sources exporting one ride create it only once', () {
      // Same ride, different record ids — the id check alone lets both through.
      final plan = resolveActivityImport(
        existing: const [],
        incoming: [
          _incoming(hcId: 'watch', distanceKm: 20),
          _incoming(hcId: 'googlefit', end: '2026-08-07T10:47:00'),
        ],
      );
      expect(plan.create, hasLength(1));
      // The richer of the two is the one kept.
      expect(plan.create.single.healthConnectRecordId, 'watch');
    });

    test('back-to-back workouts are not folded together', () {
      final plan = resolveActivityImport(
        existing: const [],
        incoming: [
          _incoming(
              hcId: 'a',
              start: '2026-08-07T10:00:00',
              end: '2026-08-07T10:30:00'),
          _incoming(
              hcId: 'b',
              start: '2026-08-07T10:30:00',
              end: '2026-08-07T11:00:00'),
        ],
      );
      expect(plan.create, hasLength(2));
    });

    test('overlapping workouts of different types are both kept', () {
      final plan = resolveActivityImport(
        existing: const [],
        incoming: [
          _incoming(hcId: 'ride'),
          _incoming(hcId: 'run', type: ActivityType.running),
        ],
      );
      expect(plan.create, hasLength(2));
    });
  });

  group('re-import of an already stored workout', () {
    test('the same record id changes nothing', () {
      final plan = resolveActivityImport(
        existing: [_stored(id: '1', hcId: 'a', end: '2026-08-07T10:45:00')],
        incoming: [_incoming(hcId: 'a')],
      );
      expect(plan.isEmpty, isTrue);
    });

    // The reported bug: Google Fit auto-detects a ride, then finalises it
    // under a NEW record id with a corrected end time.
    test('a finalised session updates the stored row instead of duplicating',
        () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'provisional', end: '2026-08-07T10:30:00'),
        ],
        incoming: [_incoming(hcId: 'final', end: '2026-08-07T10:45:00')],
      );

      expect(plan.create, isEmpty, reason: 'must not add a second copy');
      expect(plan.delete, isEmpty);
      expect(plan.update, hasLength(1));

      final merged = plan.update.single;
      expect(merged.id, '1', reason: 'updates the row in place');
      expect(merged.endTime, DateTime.parse('2026-08-07T10:45:00'),
          reason: 'the latest import wins on times');
      expect(merged.healthConnectRecordId, 'final');
    });

    test('a degraded re-export cannot blank out values already recorded', () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'old', calories: 420, distanceKm: 18.5),
        ],
        incoming: [_incoming(hcId: 'new')], // carries neither
      );
      final merged = plan.update.single;
      expect(merged.caloriesBurned, 420);
      expect(merged.distanceKm, 18.5);
    });

    test('incoming values still win where present', () {
      final plan = resolveActivityImport(
        existing: [_stored(id: '1', hcId: 'old', calories: 420)],
        incoming: [_incoming(hcId: 'new', calories: 465)],
      );
      expect(plan.update.single.caloriesBurned, 465);
    });

    test('gear the user attached survives the update', () {
      final plan = resolveActivityImport(
        existing: [_stored(id: '1', hcId: 'old', gearId: 'bike-1')],
        incoming: [_incoming(hcId: 'new')],
      );
      expect(plan.update.single.gearId, 'bike-1');
    });

    test('a zero-length session matches itself by record id', () {
      // Nothing overlaps a zero-length interval, so only the id check saves it
      // from being imported again on every single sync.
      final plan = resolveActivityImport(
        existing: [
          _stored(
              id: '1',
              hcId: 'a',
              start: '2026-08-07T10:00:00',
              end: '2026-08-07T10:00:00'),
        ],
        incoming: [
          _incoming(
              hcId: 'a',
              start: '2026-08-07T10:00:00',
              end: '2026-08-07T10:00:00'),
        ],
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('cleaning up rows that are already duplicated', () {
    test('folds two stored copies into one and deletes the loser', () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'provisional', end: '2026-08-07T10:30:00'),
          _stored(id: '2', hcId: 'final', end: '2026-08-07T10:45:00'),
        ],
        incoming: [_incoming(hcId: 'final', end: '2026-08-07T10:45:00')],
      );

      expect(plan.create, isEmpty);
      expect(plan.update, hasLength(1));
      expect(plan.delete, hasLength(1));
      // Exactly one row survives, and it is the one still referenced.
      final survivingId = plan.update.single.id;
      expect(plan.delete.single.id, isNot(survivingId));
    });

    test('keeps the copy the user attached gear to', () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'provisional'),
          _stored(id: '2', hcId: 'final', gearId: 'bike-1'),
        ],
        incoming: [_incoming(hcId: 'final')],
      );
      expect(plan.update.single.id, '2');
      expect(plan.update.single.gearId, 'bike-1');
      expect(plan.delete.single.id, '1');
    });

    test('rescues gear from the copy being deleted', () {
      // The user attached the bike to whichever copy the list happened to show.
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'provisional', gearId: 'bike-1'),
          _stored(id: '2', hcId: 'final'),
        ],
        incoming: [_incoming(hcId: 'final')],
      );
      expect(plan.delete.single.id, '2');
      expect(plan.update.single.gearId, 'bike-1',
          reason: 'the assignment must not be lost with the duplicate');
    });

    test('rescues notes from the copy being deleted', () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', hcId: 'provisional', gearId: 'bike-1'),
          _stored(id: '2', hcId: 'final', notes: 'headwind all the way back'),
        ],
        incoming: [_incoming(hcId: 'final')],
      );
      expect(plan.update.single.notes, 'headwind all the way back');
    });
  });

  group('hand-entered activities', () {
    test('a manual entry is never overwritten by an overlapping import', () {
      final plan = resolveActivityImport(
        existing: [_stored(id: '1', source: DataSource.manual)],
        incoming: [_incoming(hcId: 'a')],
      );
      expect(plan.isEmpty, isTrue);
    });

    test('a manual entry is never deleted as a duplicate', () {
      final plan = resolveActivityImport(
        existing: [
          _stored(id: '1', source: DataSource.manual),
          _stored(id: '2', hcId: 'old'),
        ],
        incoming: [_incoming(hcId: 'new')],
      );
      expect(plan.delete, isEmpty);
      expect(plan.update, isEmpty);
    });
  });

  group('convergence', () {
    // Both records staying in Health Connect must not make the two take turns
    // overwriting each other on every sync.
    test('re-running the same import a second time is a no-op', () {
      final incoming = [
        _incoming(hcId: 'watch', distanceKm: 20),
        _incoming(hcId: 'googlefit', end: '2026-08-07T10:47:00'),
      ];

      final first = resolveActivityImport(
        existing: [_stored(id: '1', hcId: 'stale', end: '2026-08-07T10:20:00')],
        incoming: incoming,
      );
      expect(first.update, hasLength(1));

      final second = resolveActivityImport(
        existing: first.update, // the state the first run left behind
        incoming: incoming,
      );
      expect(second.isEmpty, isTrue,
          reason: 'a settled import must stop changing things');
    });
  });

  group('mergeActivitiesById', () {
    test('unions both lists without duplicating a shared row', () {
      final shared = _stored(id: '1', hcId: 'a');
      final merged = mergeActivitiesById(
        [shared],
        [shared, _stored(id: '2', hcId: 'b')],
      );
      expect(merged.map((a) => a.id), containsAll(['1', '2']));
      expect(merged, hasLength(2));
    });

    test('the first list wins for a row present in both', () {
      final merged = mergeActivitiesById(
        [_stored(id: '1', hcId: 'server')],
        [_stored(id: '1', hcId: 'store')],
      );
      expect(merged.single.healthConnectRecordId, 'server');
    });

    test('keeps rows that have no id yet', () {
      final merged = mergeActivitiesById(
        [_stored(id: '1', hcId: 'a')],
        [_incoming(hcId: 'b')],
      );
      expect(merged, hasLength(2));
    });

    test('an empty server response still yields the store contents', () {
      // The case that disabled de-duplication entirely: a failed fetch looks
      // exactly like a day with no activities.
      final merged =
          mergeActivitiesById(const [], [_stored(id: '1', hcId: 'a')]);
      expect(merged, hasLength(1));
    });
  });
}
