import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/url.dart';
import 'package:http/http.dart' as http;

/// Stores offline punches in SQLite and syncs them when the device is back online.
///
/// Table: offline_punches
class OfflinePunchStore {
  OfflinePunchStore._();

  static Database? _db;

  static const String _tableName = 'offline_punches';

  // ─────────────────────────────────────────────────────────────────────────
  // Database initialisation
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'face_match_offline.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_tableName (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_no TEXT    NOT NULL,
            check_type  TEXT    NOT NULL,
            date_time   TEXT    NOT NULL,
            latitude    TEXT    DEFAULT '',
            longitude   TEXT    DEFAULT '',
            location    TEXT    DEFAULT '',
            device_id   TEXT    DEFAULT '',
            synced      INTEGER DEFAULT 0,
            synced_at   TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write
  // ─────────────────────────────────────────────────────────────────────────

  /// Persists one offline punch. Returns the inserted row ID.
  static Future<int> storePunch({
    required String employeeNo,
    required String checkType,
    required DateTime dateTime,
    String latitude = '',
    String longitude = '',
    String location = '',
    String deviceId = '',
  }) async {
    final db = await getDatabase();
    final id = await db.insert(_tableName, {
      'employee_no': employeeNo,
      'check_type': checkType,
      'date_time': dateTime.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'location': location,
      'device_id': deviceId,
      'synced': 0,
    });
    if (kDebugMode) {
      print('[OfflinePunchStore] 💾 Stored punch: $checkType for $employeeNo (id=$id)');
    }
    return id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Read
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> hasUnsynced() async {
    final count = await getUnsyncedCount();
    return count > 0;
  }

  static Future<int> getUnsyncedCount() async {
    final db = await getDatabase();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableName WHERE synced = 0',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  static Future<List<Map<String, dynamic>>> getUnsynced() async {
    final db = await getDatabase();
    return db.query(
      _tableName,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<int> deletePunch(int id) async {
    final db = await getDatabase();
    return db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> clearAllUnsynced() async {
    final db = await getDatabase();
    return db.delete(
      _tableName,
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sync
  // ─────────────────────────────────────────────────────────────────────────

  /// Uploads all unsynced rows to the server using the same IOUPDATED endpoint.
  /// Marks each row synced on success.
  static Future<OfflineSyncResult> syncUnsynced({
    void Function(int synced, int total)? onProgress,
  }) async {
    final rows = await getUnsynced();
    final total = rows.length;
    int synced = 0;

    if (total == 0) {
      return const OfflineSyncResult(syncedCount: 0, total: 0);
    }

    if (kDebugMode) {
      print('[OfflinePunchStore] 🔄 Syncing $total unsynced punch(es)...');
    }

    for (final row in rows) {
      try {
        final empId = row['employee_no'] as String;
        final checkType = row['check_type'] as String;
        final dateTime = row['date_time'] as String;
        final latitude = row['latitude'] as String? ?? '';
        final longitude = row['longitude'] as String? ?? '';
        final location = row['location'] as String? ?? '';
        final deviceId = row['device_id'] as String? ?? '';

        final params = {
          'Latitude': latitude,
          'Longitude': longitude,
          'CheckType': checkType,
          'CheckTime': dateTime,
          'Location': location,
          'Device': deviceId,
          'ProjectId': '',
          'GeoId': '',
          'GeoLocationnName': location,
        };

        final uri = Uri.parse('${Url.newCheckInURL}$empId')
            .replace(queryParameters: params);

        final response = await http.get(uri).timeout(
          const Duration(seconds: 12),
        );

        if (response.statusCode == 200) {
          await _markSynced(row['id'] as int);
          synced++;
          if (kDebugMode) {
            print('[OfflinePunchStore] ✅ Synced punch id=${row['id']} for $empId');
          }
        } else {
          if (kDebugMode) {
            print('[OfflinePunchStore] ⚠️ Server ${response.statusCode} for id=${row['id']}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[OfflinePunchStore] ❌ Sync error for id=${row['id']}: $e');
        }
      }
      onProgress?.call(synced, total);
    }

    return OfflineSyncResult(syncedCount: synced, total: total);
  }

  static Future<void> _markSynced(int id) async {
    final db = await getDatabase();
    await db.update(
      _tableName,
      {
        'synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class OfflineSyncResult {
  final int syncedCount;
  final int total;

  const OfflineSyncResult({
    required this.syncedCount,
    required this.total,
  });

  bool get fullySynced => total > 0 && syncedCount == total;
  bool get noRecords => total == 0;
  bool get stoppedEarly => !fullySynced && total > 0;

  @override
  String toString() =>
      'OfflineSyncResult(synced=$syncedCount/$total, fullySynced=$fullySynced)';
}
