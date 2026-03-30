import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

enum QueueOperation { create, update, delete }

enum QueueTable { foodEntries, physicalActivities }

class PendingOperation {
  final String id;
  final QueueTable table;
  final QueueOperation operation;
  final Map<String, dynamic> payload; // full entity JSON for create/update, {'id': '...'} for delete
  final DateTime createdAt;
  final int retryCount;

  const PendingOperation({
    required this.id,
    required this.table,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toDbRow() => {
    'id': id,
    'table_name': table.name,
    'operation': operation.name,
    'payload': jsonEncode(payload),
    'created_at': createdAt.millisecondsSinceEpoch,
    'retry_count': retryCount,
  };

  factory PendingOperation.fromDbRow(Map<String, dynamic> row) => PendingOperation(
    id: row['id'] as String,
    table: QueueTable.values.firstWhere((t) => t.name == row['table_name']),
    operation: QueueOperation.values.firstWhere((o) => o.name == row['operation']),
    payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    retryCount: row['retry_count'] as int,
  );
}

/// SQLite-backed queue for operations that could not reach the server.
/// Operations are replayed in insertion order when connectivity is restored.
class OfflineQueue {
  static final OfflineQueue instance = OfflineQueue._();
  OfflineQueue._();

  static const _dbName = 'dietry_offline.db';
  static const _tableName = 'pending_operations';
  static const _version = 1;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _version,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_tableName (
          id TEXT PRIMARY KEY,
          table_name TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
  }

  Future<void> enqueue({
    required QueueTable table,
    required QueueOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    if (kIsWeb) return; // sqflite not available on web
    final op = PendingOperation(
      id: const Uuid().v4(),
      table: table,
      operation: operation,
      payload: payload,
      createdAt: DateTime.now(),
    );
    final db = await _database;
    await db.insert(_tableName, op.toDbRow());
  }

  Future<List<PendingOperation>> getPending() async {
    if (kIsWeb) return []; // sqflite not available on web
    final db = await _database;
    final rows = await db.query(_tableName, orderBy: 'created_at ASC');
    return rows.map(PendingOperation.fromDbRow).toList();
  }

  Future<int> pendingCount() async {
    if (kIsWeb) return 0; // sqflite not available on web
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $_tableName');
    return result.first['c'] as int;
  }

  Future<void> remove(String id) async {
    if (kIsWeb) return; // sqflite not available on web
    final db = await _database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementRetry(String id) async {
    if (kIsWeb) return; // sqflite not available on web
    final db = await _database;
    await db.rawUpdate(
      'UPDATE $_tableName SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> clear() async {
    if (kIsWeb) return; // sqflite not available on web
    final db = await _database;
    await db.delete(_tableName);
  }
}
