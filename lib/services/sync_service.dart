import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/food_entry.dart';
import '../models/physical_activity.dart';
import 'food_entry_service.dart';
import 'physical_activity_service.dart';
import 'neon_database_service.dart';
import 'local_data_service.dart';
import 'offline_queue.dart';
import 'app_logger.dart';

/// Monitors connectivity and replays queued offline operations.
/// Also exposes [isOnline] and [pendingCount] for UI display.
class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  SyncService._();

  NeonDatabaseService? _db;
  LocalDataService? _local;
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _isSyncing = false;
  Timer? _pollTimer;

  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  /// Call once after [NeonDatabaseService] is ready.
  Future<void> init(NeonDatabaseService db) async {
    _db = db;
    _pendingCount = await OfflineQueue.instance.pendingCount();
    notifyListeners();

    // Poll connectivity by attempting a lightweight HEAD request every 30s.
    // connectivity_plus is not used to keep dependencies minimal; instead we
    // rely on catching DioExceptions in _tryRequest to detect offline state.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _periodicSync());
  }

  /// Initialize for guest mode (local SQLite storage)
  void initLocal(LocalDataService local) {
    _local = local;
    _isOnline = true;  // Always online in local mode (no queue)
    _pendingCount = 0;  // No offline queue in local mode
    notifyListeners();
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
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.createFoodEntry(entry);
        return result;
      } catch (e) {
        appLogger.e('❌ Error creating food entry locally: $e');
        return null;
      }
    }

    // Remote mode: existing behavior
    try {
      final result = await FoodEntryService(_db!).createFoodEntry(entry);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.foodEntries,
        operation: QueueOperation.create,
        payload: entry.toJson(),
      );
      await _refreshPendingCount();
      return null; // caller keeps the optimistic entry
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
    // Guest mode: direct local storage
    if (_local != null) {
      try {
        final result = await _local!.createActivity(activity);
        return result;
      } catch (e) {
        appLogger.e('❌ Error saving activity locally: $e');
        return null;
      }
    }

    // Remote mode: existing behavior
    try {
      final result = await PhysicalActivityService(_db!).saveActivity(activity);
      _markOnline();
      return result;
    } catch (_) {
      _markOffline();
      await OfflineQueue.instance.enqueue(
        table: QueueTable.physicalActivities,
        operation: QueueOperation.create,
        payload: activity.toJson(),
      );
      await _refreshPendingCount();
      return null;
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

  // ── Queue processing ──────────────────────────────────────────────────────

  Future<void> _periodicSync() async {
    if (_isSyncing || _db == null) return;
    await processPendingQueue();
  }

  /// Attempt to replay all queued operations in order.
  Future<void> processPendingQueue() async {
    if (_isSyncing || _db == null) return;
    final pending = await OfflineQueue.instance.getPending();
    if (pending.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    for (final op in pending) {
      final success = await _replay(op);
      if (success) {
        await OfflineQueue.instance.remove(op.id);
      } else {
        await OfflineQueue.instance.incrementRetry(op.id);
        // If the server is unreachable, stop retrying further ops this cycle.
        break;
      }
    }

    _isSyncing = false;
    await _refreshPendingCount();
  }

  Future<bool> _replay(PendingOperation op) async {
    try {
      if (op.table == QueueTable.foodEntries) {
        final svc = FoodEntryService(_db!);
        switch (op.operation) {
          case QueueOperation.create:
            await svc.createFoodEntry(FoodEntry.fromJson(op.payload));
          case QueueOperation.update:
            await svc.updateFoodEntry(FoodEntry.fromJson(op.payload));
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
      return true;
    } catch (_) {
      _markOffline();
      return false;
    }
  }

  // ── State helpers ─────────────────────────────────────────────────────────

  void _markOnline() {
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

  Future<void> _refreshPendingCount() async {
    _pendingCount = await OfflineQueue.instance.pendingCount();
    notifyListeners();
  }
}
