import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/food_entry.dart';
import '../models/gear.dart';
import '../models/physical_activity.dart';
import 'food_entry_service.dart';
import 'gear_service.dart';
import 'physical_activity_service.dart';
import 'neon_database_service.dart';
import 'local_data_service.dart';
import 'offline_queue.dart';
import 'app_logger.dart';

/// What a single queue replay attempt tells us to do with the operation.
enum _ReplayOutcome {
  /// Reached the server and was accepted (or had already been applied).
  applied,

  /// Transient failure — offline, 5xx, rate limited, or an auth problem that a
  /// later sign-in can resolve. Keep the operation and try again next cycle.
  retry,

  /// The server rejected the operation on its merits. Replaying it will never
  /// succeed, so it must be dropped rather than block the queue.
  rejected,
}

/// Monitors connectivity and replays queued offline operations.
/// Also exposes [isOnline] and [pendingCount] for UI display.
class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  SyncService._();

  NeonDatabaseService? _db;
  LocalDataService? _local;

  /// Logged-in write-through cache (offline mirror). Distinct from [_local]
  /// (the guest-mode backend); when set, [_db] is also set. Logged-in writes
  /// mirror into it so a change survives a force-quit → cold start even before
  /// the next background refresh. Attached via [attachCache].
  LocalDataService? _cache;
  bool _isOnline = true;
  bool _sessionExpired = false;
  int _pendingCount = 0;
  bool _isSyncing = false;
  Timer? _pollTimer;

  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  /// The server is reachable but rejects us, and a token refresh did not help.
  /// This is not an offline state — the UI must offer a fresh sign-in here
  /// instead of promising "changes will sync when the connection is back".
  bool get sessionExpired => _sessionExpired;

  /// How often an operation may be replayed before it is considered hopeless
  /// and dropped. Stops a single entry from blocking the queue — and with it
  /// the sync indicator — forever.
  static const int _maxReplayAttempts = 25;

  /// Call once after [NeonDatabaseService] is ready.
  Future<void> init(NeonDatabaseService db) async {
    _db = db;
    // Drop any guest-mode local backend so write-through and reads go to the
    // server after a guest→login transition. The service is a singleton and
    // its write methods check _local before _db, so a lingering guest instance
    // would otherwise send post-login writes to the wiped guest SQLite. See
    // initLocal().
    _local = null;
    // Re-attached per session in _initializeAndLoadData() once the user id
    // resolves; clear any stale cache from a previous login.
    _cache = null;
    _isOnline = true;
    _sessionExpired = false;
    _pendingCount = await OfflineQueue.instance.pendingCount();
    notifyListeners();

    // Every 30s: check reachability first, then drain the queue.
    // connectivity_plus is deliberately not used (no extra dependency) —
    // [checkConnectivity] asks the Data API itself, which is the only question
    // that actually matters here.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _periodicSync());
  }

  /// Initialize for guest mode (local SQLite storage)
  void initLocal(LocalDataService local) {
    _local = local;
    // Guest and authenticated modes are mutually exclusive; keep exactly one
    // backend set so write-through dispatch is unambiguous.
    _db = null;
    // The logged-in write-through cache only applies in authenticated mode; in
    // guest mode _local is already the source of truth.
    _cache = null;
    _isOnline = true;  // Always online in local mode (no queue)
    _sessionExpired = false;  // No server session to expire in guest mode
    _pendingCount = 0;  // No offline queue in local mode
    notifyListeners();
  }

  /// Attach the per-user local cache (offline mirror, logged-in mode) so writes
  /// mirror into it immediately. Must already be init()'d with the real user id.
  void attachCache(LocalDataService cache) {
    _cache = cache;
  }

  /// Best-effort write-through of a logged-in mutation into the local cache.
  /// Never throws — a cache failure must not affect the user-facing operation.
  Future<void> _mirrorToCache(
      Future<void> Function(LocalDataService cache) op) async {
    final c = _cache;
    if (c == null) return;
    try {
      await op(c);
    } catch (e) {
      appLogger.w('⚠️ Cache write-through failed: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Write-through helpers ─────────────────────────────────────────────────

  /// Create a food entry. Returns the server-assigned entity (with real id/timestamps),
  /// or null if the operation was queued for later.
  Future<FoodEntry?> createFoodEntry(FoodEntry entry) async {
    // Assign a stable client id up-front so the optimistic UI entry, the remote
    // insert and any queued replay all share one identity (idempotent writes).
    final e = entry.id.isEmpty ? entry.copyWith(id: const Uuid().v4()) : entry;

    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.createFoodEntry(e);
        return result;
      } catch (err) {
        appLogger.e('❌ Error creating food entry locally: $err');
        return null;
      }
    }

    // Logged-in: mirror into the local cache so a cold start reflects the add
    // even before the next background refresh; then write to the server.
    await _mirrorToCache((c) => c.cacheUpsertFoodEntry(e));

    // Remote mode: existing behavior
    try {
      final result = await FoodEntryService(_db!).createFoodEntry(e);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.foodEntries,
        operation: QueueOperation.create,
        payload: e.toJson(),
      );
      await _refreshPendingCount();
      // Return the entry with its assigned id (was null) so the caller's
      // optimistic add carries the same id the queued replay will insert.
      return e;
    }
  }

  Future<FoodEntry?> updateFoodEntry(FoodEntry entry) async {
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.updateFoodEntry(entry);
        return result;
      } catch (e) {
        appLogger.e('❌ Error updating food entry locally: $e');
        return null;
      }
    }

    // Logged-in: mirror the edit into the local cache, then write to the server.
    await _mirrorToCache((c) => c.cacheUpsertFoodEntry(entry));

    // Remote mode: existing behavior
    try {
      final result = await FoodEntryService(_db!).updateFoodEntry(entry);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.foodEntries,
        operation: QueueOperation.update,
        payload: entry.toJson(),
      );
      await _refreshPendingCount();
      return null;
    }
  }

  Future<void> deleteFoodEntry(String id) async {
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        await _local!.deleteFoodEntry(id);
        return;
      } catch (e) {
        appLogger.e('❌ Error deleting food entry locally: $e');
        return;
      }
    }

    // Logged-in: mirror the delete into the local cache, then hit the server.
    await _mirrorToCache((c) => c.deleteFoodEntry(id));

    // Remote mode: existing behavior
    try {
      await FoodEntryService(_db!).deleteFoodEntry(id);
      _markOnline();
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.foodEntries,
        operation: QueueOperation.delete,
        payload: {'id': id},
      );
      await _refreshPendingCount();
    }
  }

  Future<PhysicalActivity?> saveActivity(PhysicalActivity activity) async {
    // Assign a stable client id up-front (see createFoodEntry). PhysicalActivity
    // uses a nullable id, so treat null or empty as "needs one".
    final a = (activity.id == null || activity.id!.isEmpty)
        ? activity.copyWith(id: const Uuid().v4())
        : activity;

    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.createActivity(a);
        return result;
      } catch (e) {
        appLogger.e('❌ Error saving activity locally: $e');
        return null;
      }
    }

    // Logged-in: mirror into the local cache, then write to the server.
    await _mirrorToCache((c) => c.cacheUpsertActivity(a));

    // Remote mode: existing behavior
    try {
      final result = await PhysicalActivityService(_db!).saveActivity(a);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.physicalActivities,
        operation: QueueOperation.create,
        payload: a.toJson(),
      );
      await _refreshPendingCount();
      // Return the activity with its assigned id (was null) so the caller's
      // optimistic add matches the id the queued replay will insert.
      return a;
    }
  }

  Future<PhysicalActivity?> updateActivity(PhysicalActivity activity) async {
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.updateActivity(activity);
        return result;
      } catch (e) {
        appLogger.e('❌ Error updating activity locally: $e');
        return null;
      }
    }

    // Logged-in: mirror the edit into the local cache, then write to the server.
    await _mirrorToCache((c) => c.cacheUpsertActivity(activity));

    // Remote mode: existing behavior
    try {
      final result = await PhysicalActivityService(_db!).updateActivity(activity);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.physicalActivities,
        operation: QueueOperation.update,
        payload: activity.toJson(),
      );
      await _refreshPendingCount();
      return null;
    }
  }

  Future<void> deleteActivity(String id) async {
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        await _local!.deleteActivity(id);
        return;
      } catch (e) {
        appLogger.e('❌ Error deleting activity locally: $e');
        return;
      }
    }

    // Logged-in: mirror the delete into the local cache, then hit the server.
    await _mirrorToCache((c) => c.deleteActivity(id));

    // Remote mode: existing behavior
    try {
      await PhysicalActivityService(_db!).deleteActivity(id);
      _markOnline();
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.physicalActivities,
        operation: QueueOperation.delete,
        payload: {'id': id},
      );
      await _refreshPendingCount();
    }
  }

  // ── Gear ──────────────────────────────────────────────────────────────────
  // Gear mutations are rare (you buy shoes once) and are not offline-queued —
  // an offline create simply fails and is reported. Reads still work offline
  // from the mirror, which is what matters for attaching gear to a workout.

  Future<List<Gear>> getGear() async {
    if (_local != null) return _local!.getGear();
    if (_db == null) return [];
    try {
      final gear = await GearService(_db!).getGear();
      _markOnline();
      // Refresh the mirror so the gear picker keeps working offline — but never
      // with an empty list. GearService answers *any* failure (an unusable
      // token on a cold start above all) with [], which is indistinguishable
      // from "owns no gear", and mirroring that wipes the offline list.
      if (gear.isNotEmpty) {
        await _mirrorToCache((c) => c.replaceCachedGear(gear));
        return gear;
      }
      final cache = _cache;
      if (cache == null) return gear;
      final cached = await cache.getGear();
      if (cached.isNotEmpty) {
        appLogger.w('⚠️ Gear came back empty — using the mirrored list');
      }
      return cached;
    } catch (_) {
      _markOffline();
      // Fall back to the last mirrored list rather than showing "no gear".
      final cache = _cache;
      if (cache == null) return <Gear>[];
      return cache.getGear();
    }
  }

  /// Lifetime totals per gear id. Guest mode sums the local store (which holds
  /// the full history); logged-in goes to the server, because the local mirror
  /// only keeps ~30 days and would under-report.
  Future<Map<String, GearTotals>> getGearTotals() async {
    if (_local != null) return _local!.getGearTotals();
    if (_db == null) return {};
    return GearService(_db!).getTotals();
  }

  Future<Gear?> saveGear(Gear gear) async {
    final g = (gear.id == null || gear.id!.isEmpty)
        ? gear.copyWith(id: const Uuid().v4())
        : gear;

    if (_local != null) {
      try {
        return await _local!.createGear(g);
      } catch (e) {
        appLogger.e('❌ Error saving gear locally: $e');
        return null;
      }
    }
    if (_db == null) return null;

    final created = await GearService(_db!).createGear(g);
    _markOnline();
    await _mirrorToCache((c) => c.createGear(created));
    return created;
  }

  Future<Gear?> updateGear(Gear gear) async {
    if (_local != null) {
      try {
        return await _local!.updateGear(gear);
      } catch (e) {
        appLogger.e('❌ Error updating gear locally: $e');
        return null;
      }
    }
    if (_db == null) return null;

    final updated = await GearService(_db!).updateGear(gear);
    _markOnline();
    await _mirrorToCache((c) => c.updateGear(updated));
    return updated;
  }

  Future<void> deleteGear(String id) async {
    if (_local != null) {
      await _local!.deleteGear(id);
      return;
    }
    if (_db == null) return;

    await GearService(_db!).deleteGear(id);
    _markOnline();
    await _mirrorToCache((c) => c.deleteGear(id));
  }

  // ── Queue processing ──────────────────────────────────────────────────────

  Future<void> _periodicSync() async {
    if (_db == null) return;
    // Probe reachability while we still believe we are offline. Without this
    // step [_isOnline] could never become true again: the only way back was a
    // *successful* write, and with an empty queue nothing happened here at all.
    // A single network hiccup therefore pinned the app in "offline" forever —
    // across restarts too, because the next failing request followed
    // immediately on startup.
    if (!_isOnline) await checkConnectivity();
    if (_isSyncing) return;
    await processPendingQueue();
  }

  /// Fragt die Data API, ob sie erreichbar ist, und aktualisiert [isOnline].
  /// Jede HTTP-Antwort zählt als "online" — auch eine ablehnende: dass der
  /// Server antwortet, ist die Aussage, um die es dem Offline-Banner geht.
  Future<bool> checkConnectivity() async {
    final db = _db;
    if (db == null) return _isOnline;

    final reachable = await db.ping();
    if (reachable) {
      _markReachable();
    } else {
      _markOffline();
    }
    return reachable;
  }

  /// Attempt to replay all queued operations in order.
  Future<void> processPendingQueue() async {
    if (_isSyncing || _db == null) return;
    final pending = await OfflineQueue.instance.getPending();
    if (pending.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    for (final op in pending) {
      final outcome = await _replay(op);

      if (outcome == _ReplayOutcome.applied) {
        await OfflineQueue.instance.remove(op.id);
        continue;
      }

      if (outcome == _ReplayOutcome.rejected) {
        // The server rejected this operation on its merits (malformed payload,
        // violated constraint, row already gone). Retrying changes nothing.
        // Such an operation used to sit at the head of the queue forever,
        // failing every sync cycle and keeping the red offline banner up for
        // good — drop it and move on.
        appLogger.w(
            '🗑️ Dropping permanently rejected sync operation: ${op.table.name}/${op.operation.name} (${op.id})');
        await OfflineQueue.instance.remove(op.id);
        continue;
      }

      // Transient failure (network, 5xx, auth). Bump the counter and stop this
      // cycle, which preserves the ordering of the remaining operations.
      await OfflineQueue.instance.incrementRetry(op.id);
      if (op.retryCount + 1 >= _maxReplayAttempts) {
        appLogger.w(
            '🗑️ Giving up on sync operation after ${op.retryCount + 1} attempts: ${op.table.name}/${op.operation.name} (${op.id})');
        await OfflineQueue.instance.remove(op.id);
        continue;
      }
      break;
    }

    _isSyncing = false;
    await _refreshPendingCount();
  }

  Future<_ReplayOutcome> _replay(PendingOperation op) async {
    try {
      if (op.table == QueueTable.foodEntries) {
        final svc = FoodEntryService(_db!);
        switch (op.operation) {
          case QueueOperation.create:
            await svc.createFoodEntry(
                FoodEntry.fromJson(_scrubBlankFoodId(op.payload)));
          case QueueOperation.update:
            await svc.updateFoodEntry(
                FoodEntry.fromJson(_scrubBlankFoodId(op.payload)));
          case QueueOperation.delete:
            await svc.deleteFoodEntry(op.payload['id'] as String);
        }
      } else {
        final svc = PhysicalActivityService(_db!);
        switch (op.operation) {
          case QueueOperation.create:
            await svc.saveActivity(PhysicalActivity.fromJson(op.payload));
          case QueueOperation.update:
            await svc.updateActivity(PhysicalActivity.fromJson(op.payload));
          case QueueOperation.delete:
            await svc.deleteActivity(op.payload['id'] as String);
        }
      }
      _markOnline();
      return _ReplayOutcome.applied;
    } on DioException catch (e) {
      // A queued create whose HTTP response was lost may already have committed
      // server-side; the replay then hits a duplicate-key (409 Conflict) on the
      // client-supplied id. Now that ids are client-generated this is the
      // "already applied" case — treat it as success so the op drains instead
      // of wedging the queue on every cycle.
      if (op.operation == QueueOperation.create &&
          e.response?.statusCode == 409) {
        appLogger.i('↩️ Replay: create already applied (409) — treating as done');
        _markOnline();
        return _ReplayOutcome.applied;
      }

      final status = e.response?.statusCode;

      // No response at all → transport failure, i.e. genuinely offline.
      if (status == null) {
        _markOffline();
        return _ReplayOutcome.retry;
      }

      // The server answered, so the network is fine.
      _markReachable();

      // Auth failure: the Dio interceptor already tried to refresh and failed,
      // otherwise the request would have been retried transparently. Keep the
      // operation — it becomes replayable again after a fresh sign-in.
      if (NeonDatabaseService.isAuthFailureResponse(e.response)) {
        return _ReplayOutcome.retry;
      }

      // 5xx and 429: the server is unhappy right now, not with this payload.
      if (status >= 500 || status == 429) {
        return _ReplayOutcome.retry;
      }

      // Any other 4xx is a verdict on the operation itself (malformed payload,
      // constraint violation, row already deleted). Replaying it will fail
      // identically forever, so let the caller drop it.
      if (status >= 400) {
        appLogger.w('⚠️ Replay rejected with $status: ${e.response?.data}');
        return _ReplayOutcome.rejected;
      }

      return _ReplayOutcome.retry;
    } catch (_) {
      _markOffline();
      return _ReplayOutcome.retry;
    }
  }

  /// Removes `food_id` from [payload] when it's a blank string. Postgres
  /// rejects empty strings as `uuid`, and historical OFF-barcode bugs
  /// queued create-ops with this shape — without scrubbing, the bad op
  /// would block every later sync (the replay loop breaks on first
  /// failure). Returns the same map when nothing needs changing so we
  /// don't allocate on the happy path.
  Map<String, dynamic> _scrubBlankFoodId(Map<String, dynamic> payload) {
    final fid = payload['food_id'];
    if (fid is String && fid.trim().isEmpty) {
      final scrubbed = Map<String, dynamic>.from(payload)..remove('food_id');
      return scrubbed;
    }
    return payload;
  }

  // ── State helpers ─────────────────────────────────────────────────────────

  /// A request went through and was accepted: we are online *and* authenticated.
  void _markOnline() {
    if (!_isOnline || _sessionExpired) {
      _isOnline = true;
      _sessionExpired = false;
      notifyListeners();
    }
  }

  /// The server answered — whatever it said. That settles connectivity but says
  /// nothing about our session, so [_sessionExpired] is left alone.
  void _markReachable() {
    if (!_isOnline) {
      _isOnline = true;
      notifyListeners();
    }
  }

  void _markOffline() {
    if (_isOnline) {
      _isOnline = false;
      notifyListeners();
    }
  }

  /// The server is reachable but rejects our token and a refresh could not fix
  /// it. Called from the database service's auth-recovery hook.
  ///
  /// Reaching the server at all proves connectivity, so this also clears the
  /// offline flag — showing "offline, will sync later" here would be a lie, and
  /// it is exactly what left the app looking permanently disconnected while the
  /// network was fine.
  void markSessionExpired() {
    if (_sessionExpired && _isOnline) return;
    _sessionExpired = true;
    _isOnline = true;
    notifyListeners();
  }

  Future<void> _refreshPendingCount() async {
    _pendingCount = await OfflineQueue.instance.pendingCount();
    notifyListeners();
  }
}
