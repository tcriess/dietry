import '../models/physical_activity.dart';

/// What a Health Connect import should do to the activities already stored.
///
/// [update] and [delete] are ordered so the deletes must be executed FIRST: a
/// duplicate about to be removed may still hold the Health Connect record id
/// that an update is about to move onto the surviving row, and
/// `UNIQUE(user_id, health_connect_record_id)` would reject that.
class ActivityImportPlan {
  /// Workouts not stored in any form yet.
  final List<PhysicalActivity> create;

  /// Stored rows to overwrite, already merged with the incoming record and
  /// carrying their original id.
  final List<PhysicalActivity> update;

  /// Stored rows that turned out to be duplicates of a workout kept elsewhere
  /// in [update]. Always Health-Connect-sourced; never hand-entered.
  final List<PhysicalActivity> delete;

  /// Incoming records the import deliberately did not apply: a session that
  /// only summarises other records in the same batch, or one that matched
  /// several stored workouts which are not the same workout as each other.
  /// Reported so the skip is visible in the log rather than silent.
  final List<PhysicalActivity> ambiguous;

  const ActivityImportPlan({
    this.create = const [],
    this.update = const [],
    this.delete = const [],
    this.ambiguous = const [],
  });

  bool get isEmpty => create.isEmpty && update.isEmpty && delete.isEmpty;
}

/// Decides how an incoming batch of Health Connect workouts reconciles with
/// what is already stored for the same day.
///
/// The problem this solves: the same real-world workout reaches us more than
/// once under *different* record ids. Google Fit auto-detects a ride and writes
/// a provisional session, then finalises it with a corrected end time; a watch
/// app and Google Fit both export the same run. Matching on the record id alone
/// lets every one of those through and the workout shows up twice.
///
/// Resolution rules:
///   * Identity is activity type plus a time overlap (or an identical record
///     id, which also covers a zero-length session).
///   * On a conflict the latest import wins — its times replace the stored
///     ones, since correcting a provisional end time is the whole point.
///   * A hand-entered activity is never touched. The rule is about imports
///     resolving each other, not a licence to overwrite what the user typed.
///   * Values the incoming record lacks fall back to the stored ones, because
///     a re-export can arrive degraded (Google Fit re-exporting a watch
///     workout without its calorie total).
///   * Gear and notes the user attached survive, including when the row they
///     were attached to is the duplicate being removed.
ActivityImportPlan resolveActivityImport({
  required List<PhysicalActivity> existing,
  required List<PhysicalActivity> incoming,
}) {
  final create = <PhysicalActivity>[];
  final update = <PhysicalActivity>[];
  final delete = <PhysicalActivity>[];

  // A session that merely spans other sessions in the same batch describes no
  // workout of its own, and applying it can only distort one — see
  // [_partitionSummaries].
  final (workouts, ambiguous) = _partitionSummaries(incoming);

  // Richer records (distance / steps / heart rate present) first, so each
  // group's representative is the copy carrying the most data. Ordering is
  // fully determined by the data, which is what stops two records of one
  // workout from taking turns overwriting each other on every sync.
  final ordered = [...workouts]
    ..sort((a, b) {
      final byRichness = _richness(b).compareTo(_richness(a));
      if (byRichness != 0) return byRichness;
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return (a.healthConnectRecordId ?? '')
          .compareTo(b.healthConnectRecordId ?? '');
    });

  for (final group in _groupByWorkout(ordered)) {
    final representative = group.first;
    final stored =
        existing.where((e) => _sameWorkout(e, representative)).toList();

    if (stored.isEmpty) {
      create.add(representative);
      continue;
    }

    if (stored.any((e) => e.source != DataSource.healthConnect)) continue;

    // One incoming record stands for exactly one workout. When it matches
    // stored rows that are *not* the same workout as each other, it is a
    // session spanning them rather than a copy of any one of them — Google Fit
    // auto-detects the whole outing alongside the individual legs, and a ride
    // there and back becomes a single 17:31–18:45 record over two 20-minute
    // rides that do not overlap at all.
    //
    // Grouping is transitive, so that one record drags both stored rides into
    // the same group, and the later ride would be deleted as a "duplicate" of
    // the earlier one. The next sync, whose batch no longer carries the
    // spanning record, then re-creates it — which is exactly the delete-one-
    // and-both-come-back loop this guard exists to stop. Nothing here can tell
    // which ride the record belongs to, so it must touch none of them.
    if (_overlapClusters(stored) > 1) {
      ambiguous.add(representative);
      continue;
    }

    // Keep the row the user has since attached gear or a note to — losing that
    // costs them work, losing an auto-imported twin costs nothing.
    stored.sort((a, b) {
      final byContext =
          (_hasUserContext(a) ? 0 : 1).compareTo(_hasUserContext(b) ? 0 : 1);
      return byContext != 0 ? byContext : a.startTime.compareTo(b.startTime);
    });
    final survivor = stored.first;
    final duplicates = stored.skip(1).toList();

    // Gear the import can attach that the stored row is missing. Auto-attach
    // only fires when exactly one piece of gear claims the activity type, and
    // it silently does nothing when the gear list failed to load (the service
    // answers an error with an empty list) — so a workout imported during a
    // token refresh keeps no gear, and every later import used to skip it as
    // "already current". Re-attaching gear the user deliberately cleared is the
    // accepted cost: the same unambiguous default would be re-offered anyway.
    final gearToAttach =
        survivor.gearId == null ? representative.gearId : null;

    // Already current and not duplicated.
    if (duplicates.isEmpty &&
        gearToAttach == null &&
        survivor.healthConnectRecordId ==
            representative.healthConnectRecordId) {
      continue;
    }

    String? rescuedGearId;
    String? rescuedNotes;
    for (final duplicate in duplicates) {
      rescuedGearId ??= duplicate.gearId;
      rescuedNotes ??= _emptyToNull(duplicate.notes);
    }
    delete.addAll(duplicates);

    update.add(_merge(
      survivor,
      representative,
      gearId: survivor.gearId ?? rescuedGearId ?? gearToAttach,
      notes: _emptyToNull(survivor.notes) ?? rescuedNotes,
    ));
  }

  // Chronological, so newly saved activities land in time order.
  create.sort((a, b) => a.startTime.compareTo(b.startTime));
  return ActivityImportPlan(
    create: create,
    update: update,
    delete: delete,
    ambiguous: ambiguous,
  );
}

/// Union of two activity lists, keyed by id, first occurrence winning.
///
/// Used to build the import's baseline from both the server rows and the
/// in-memory store: `getActivitiesInRange()` returns an EMPTY LIST on any
/// failure rather than throwing, and reconciling against an empty baseline
/// silently disables every rule above — one of the ways a workout ends up
/// stored twice in the first place.
List<PhysicalActivity> mergeActivitiesById(
  List<PhysicalActivity> first,
  List<PhysicalActivity> second,
) {
  final byId = <String, PhysicalActivity>{};
  final unkeyed = <PhysicalActivity>[];
  for (final activity in [...first, ...second]) {
    final id = activity.id;
    if (id == null) {
      unkeyed.add(activity);
    } else {
      byId.putIfAbsent(id, () => activity);
    }
  }
  return [...byId.values, ...unkeyed];
}

/// True when [a] and [b] look like the same real-world workout: same
/// [ActivityType] and overlapping time intervals.
bool activitiesOverlap(PhysicalActivity a, PhysicalActivity b) {
  if (a.activityType != b.activityType) return false;
  return a.startTime.isBefore(b.endTime) && b.startTime.isBefore(a.endTime);
}

/// Splits [incoming] into the records that describe a workout and the ones that
/// only summarise others in the same batch.
///
/// Google Fit auto-detects the whole outing alongside the individual legs, so a
/// ride there and back arrives as three records: 17:31-17:51, 18:24-18:45 and
/// one 17:31-18:45 covering both. The wide one is not a third ride and it is
/// not a correction of either — it is a container, and it carries the summed
/// distance and calories of both legs. Applying it double-counts the outing;
/// worse, grouping is transitive, so it chains both legs into one group and the
/// second leg would be resolved away as a duplicate of the first.
///
/// A record counts as a summary only when it strictly contains **two** records
/// that are not the same workout as each other. One contained record is the
/// ordinary case of a provisional session finalised with a corrected end time,
/// and that has to keep working.
(List<PhysicalActivity>, List<PhysicalActivity>) _partitionSummaries(
  List<PhysicalActivity> incoming,
) {
  bool contains(PhysicalActivity outer, PhysicalActivity inner) =>
      !identical(outer, inner) &&
      outer.activityType == inner.activityType &&
      !inner.startTime.isBefore(outer.startTime) &&
      !inner.endTime.isAfter(outer.endTime) &&
      inner.endTime.difference(inner.startTime) <
          outer.endTime.difference(outer.startTime);

  bool isSummary(PhysicalActivity candidate) {
    final inside = incoming.where((r) => contains(candidate, r)).toList();
    for (var i = 0; i < inside.length; i++) {
      for (var j = i + 1; j < inside.length; j++) {
        if (!activitiesOverlap(inside[i], inside[j])) return true;
      }
    }
    return false;
  }

  final workouts = <PhysicalActivity>[];
  final summaries = <PhysicalActivity>[];
  for (final record in incoming) {
    (isSummary(record) ? summaries : workouts).add(record);
  }
  return (workouts, summaries);
}

/// How many distinct workouts [stored] holds — rows chained together by a
/// direct time overlap (or a shared record id) count as one.
int _overlapClusters(List<PhysicalActivity> stored) {
  final clusters = <List<PhysicalActivity>>[];
  for (final activity in stored) {
    final matches = clusters
        .where((c) => c.any((member) => _sameWorkout(member, activity)))
        .toList();
    if (matches.isEmpty) {
      clusters.add([activity]);
      continue;
    }
    // Bridging two clusters merges them: A–B and B–C makes one workout.
    final merged = matches.first..add(activity);
    for (final other in matches.skip(1)) {
      merged.addAll(other);
      clusters.remove(other);
    }
  }
  return clusters.length;
}

List<List<PhysicalActivity>> _groupByWorkout(List<PhysicalActivity> ordered) {
  final groups = <List<PhysicalActivity>>[];
  for (final activity in ordered) {
    List<PhysicalActivity>? match;
    for (final group in groups) {
      if (group.any((member) => activitiesOverlap(member, activity))) {
        match = group;
        break;
      }
    }
    if (match == null) {
      groups.add([activity]);
    } else {
      match.add(activity);
    }
  }
  return groups;
}

/// The record-id check is what catches a zero-length session, which
/// [activitiesOverlap] can never match — not even against itself.
bool _sameWorkout(PhysicalActivity stored, PhysicalActivity incoming) {
  final storedId = stored.healthConnectRecordId;
  if (storedId != null && storedId == incoming.healthConnectRecordId) {
    return true;
  }
  return activitiesOverlap(stored, incoming);
}

bool _hasUserContext(PhysicalActivity a) =>
    a.gearId != null || _emptyToNull(a.notes) != null;

String? _emptyToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;

int _richness(PhysicalActivity a) =>
    (a.caloriesBurned != null ? 1 : 0) +
    (a.distanceKm != null ? 1 : 0) +
    (a.steps != null ? 1 : 0) +
    (a.avgHeartRate != null ? 1 : 0);

PhysicalActivity _merge(
  PhysicalActivity stored,
  PhysicalActivity incoming, {
  String? gearId,
  String? notes,
}) {
  // Classification travels as a pair. `activityId` is the link to the
  // activity_database row the name and MET value come from, so taking the id
  // from one record and the name from the other would show one activity's
  // label against another's energy maths.
  //
  // An import whose activity_database lookup came back empty carries Health
  // Connect's raw wording — "Biking" rather than "Radfahren (normal)" — and no
  // id. That lookup fails silently (the service returns [] on error), so it
  // must never be allowed to overwrite a row that was classified properly. The
  // reverse is welcome: a classified re-import upgrades a raw stored name.
  final takeIncomingClassification =
      incoming.activityId != null || stored.activityId == null;

  return PhysicalActivity(
    id: stored.id,
    activityType: incoming.activityType,
    activityId:
        takeIncomingClassification ? incoming.activityId : stored.activityId,
    activityName: takeIncomingClassification
        ? incoming.activityName
        : stored.activityName,
    startTime: incoming.startTime,
    endTime: incoming.endTime,
    durationMinutes: incoming.durationMinutes ?? stored.durationMinutes,
    caloriesBurned: incoming.caloriesBurned ?? stored.caloriesBurned,
    distanceKm: incoming.distanceKm ?? stored.distanceKm,
    steps: incoming.steps ?? stored.steps,
    avgHeartRate: incoming.avgHeartRate ?? stored.avgHeartRate,
    notes: notes,
    source: DataSource.healthConnect,
    healthConnectRecordId:
        incoming.healthConnectRecordId ?? stored.healthConnectRecordId,
    gearId: gearId,
  );
}
