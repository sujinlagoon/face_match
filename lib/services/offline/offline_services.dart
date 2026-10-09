// offline_services.dart
//
// Central hub for all offline functionality in face_match.
//
// Mirrors Timetick's OfflineServices pattern:
//   1. Uses [ShiftWindowCalculator] for shift-aware punch windows
//   2. Checks **unsynced SQLite records first** (highest priority)
//   3. Falls back to **cached attendance history** (server-synced)
//   4. Defaults to 'checkout' when no data is available
//
// All heavy-lifting (cache I/O, SQLite) is delegated to
// [OfflineCacheService] and [OfflinePunchStore].

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/attendance_history_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/url.dart';
import '../../main_screens/model/checkstatus_model.dart';
import 'offline_cache_service.dart';
import 'offline_punch_store.dart';
import 'shift/shift_window_calculator.dart';

class OfflineServices {
  OfflineServices._();

  // ─────────────────────────────────────────────────────────────────────────
  // SHIFT AVAILABILITY & NETWORK SYNC
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks whether a valid shift with defined timings is cached and available for [employeeNo].
  static Future<bool> isShiftAvailable(String employeeNo) async {
    final shift = await OfflineCacheService.getShift(employeeNo);
    return shift != null && shift.hasValidTiming;
  }

  /// Fetches shift from ShiftMasterAPI for [employeeNo] and caches it.
  /// Returns the parsed [ShiftModel] if successful, or null on failure.
  static Future<ShiftModel?> fetchAndCacheShift(String employeeNo) async {
    try {
      final uri = Uri.parse('${Url.shiftMaster}?EmployeeNo=$employeeNo');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final shift = ShiftModel.firstFromJson(
          response.body,
          employeeNo: employeeNo,
        );
        if (shift != null) {
          await OfflineCacheService.cacheShift(employeeNo, shift);
          if (kDebugMode) {
            print('[OfflineServices] ✅ Shift cached for $employeeNo: '
                '${shift.shiftName} (${shift.inTime} – ${shift.outTime})');
          }
          return shift;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[OfflineServices] ⚠️ fetchAndCacheShift error for $employeeNo: $e');
      }
      return null;
    }
  }

  /// Fetches attendance history from AttendanceHistory API for [employeeNo] and caches it.
  /// Returns the parsed list if successful, or null on failure.
  static Future<List<AttendanceHistoryModel>?> fetchAndCacheAttendanceHistory(
      String employeeNo) async {
    try {
      final uri = Uri.parse('${Url.attendanceHistory}?EmployeeNo=$employeeNo');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = AttendanceHistoryModel.listFromJson(
          response.body,
          employeeNo: employeeNo,
        );
        await OfflineCacheService.cacheHistory(employeeNo, list);
        if (kDebugMode) {
          print('[OfflineServices] ✅ History cached for $employeeNo (${list.length} records)');
        }
        return list;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[OfflineServices] ⚠️ fetchAndCacheAttendanceHistory error for $employeeNo: $e');
      }
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIMARY: Determine offline check status for [employeeNo]
  // ─────────────────────────────────────────────────────────────────────────

  /// Determines the offline check status for [employeeNo].
  ///
  /// Resolution order (same as Timetick):
  ///   1. **Unsynced SQLite punch records** — most recent IN/OUT in window
  ///   2. **Cached attendance history** — server-synced entry in window
  ///   3. **Cached derived status** — written after each offline punch
  ///   4. **Default: checkout** — safe fallback (next punch = check-in)
  ///
  /// [shift] is loaded from [OfflineCacheService.getShift] — pass it in
  /// if already available to avoid a second read.
  static Future<CheckStatusModel> determineCheckStatus(
    String employeeNo, {
    ShiftModel? shift,
    DateTime? at,
  }) async {
    final DateTime now = at ?? DateTime.now();

    // Load shift if not provided
    final ShiftModel? resolvedShift =
        shift ?? await OfflineCacheService.getShift(employeeNo);

    // Resolve active window using the shift module
    final ShiftWindow window = ShiftWindowCalculator.resolveActiveWindow(
      shift: resolvedShift,
      at: now,
    );

    if (kDebugMode) {
      print('[OfflineServices] Window for $employeeNo: $window');
    }

    // 1. Unsynced SQLite records — highest priority
    final String? fromLocal =
        await _resolveFromUnsyncedRecords(employeeNo, window);
    if (fromLocal != null) {
      if (kDebugMode) {
        print('[OfflineServices] ✅ Status from unsynced DB: $fromLocal');
      }
      return _buildStatus(fromLocal, now);
    }

    // 2. Cached attendance history (server-synced)
    final CheckStatusModel? fromHistory =
        await _resolveFromHistory(employeeNo, window, now);
    if (fromHistory != null) {
      if (kDebugMode) {
        print('[OfflineServices] ✅ Status from history: ${fromHistory.status}');
      }
      return fromHistory;
    }

    // 3. Previously cached derived status (written after an offline punch)
    final CheckStatusModel? cached =
        await OfflineCacheService.getCheckStatus(employeeNo);
    if (cached != null) {
      if (kDebugMode) {
        print('[OfflineServices] ✅ Status from derived cache: ${cached.status}');
      }
      return cached;
    }

    // 4. Default: checkout
    if (kDebugMode) {
      print('[OfflineServices] ℹ️ No data — defaulting to checkout');
    }
    return _buildStatus('checkout', now);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Source 1: Unsynced SQLite records
  // ─────────────────────────────────────────────────────────────────────────

  /// Scans unsynced rows for [employeeNo] within the active shift window.
  /// Returns the status string ('checkin' or 'checkout') from the latest
  /// local unsynced punch, or null if no unsynced punch exists in the window.
  static Future<String?> resolveFromUnsyncedRecords(
    String employeeNo, {
    ShiftModel? shift,
    DateTime? at,
  }) async {
    final DateTime now = at ?? DateTime.now();
    final ShiftModel? resolvedShift =
        shift ?? await OfflineCacheService.getShift(employeeNo);
    final ShiftWindow window = ShiftWindowCalculator.resolveActiveWindow(
      shift: resolvedShift,
      at: now,
    );
    return _resolveFromUnsyncedRecords(employeeNo, window);
  }

  /// Scans unsynced rows for [employeeNo] newest → oldest.
  /// Returns the status string from the first punch that falls in [window].
  static Future<String?> _resolveFromUnsyncedRecords(
    String employeeNo,
    ShiftWindow window,
  ) async {
    try {
      final db = await OfflinePunchStore.getDatabase();
      final rows = await db.query(
        'offline_punches',
        where: 'synced = ? AND employee_no = ?',
        whereArgs: [0, employeeNo],
        orderBy: 'id DESC',
      );

      for (final row in rows) {
        final String? rawType = row['check_type'] as String?;
        final String? rawTime = row['date_time'] as String?;
        if (rawType == null || rawTime == null) continue;

        DateTime punchTime;
        try {
          punchTime = DateTime.parse(rawTime);
        } catch (_) {
          continue;
        }

        if (!ShiftWindowCalculator.isInWindow(punchTime, window)) continue;

        // Map check_type → status (latest punch in window wins)
        final upper = rawType.toUpperCase();
        if (upper.contains('OUT')) return 'checkout';
        if (upper.contains('IN')) return 'checkin';
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OfflineServices] ⚠️ Unsynced DB read error: $e');
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Source 2: Cached attendance history
  // ─────────────────────────────────────────────────────────────────────────

  static Future<CheckStatusModel?> _resolveFromHistory(
    String employeeNo,
    ShiftWindow window,
    DateTime now,
  ) async {
    try {
      final history = await OfflineCacheService.getHistory(employeeNo);
      if (history.isEmpty) return null;

      final AttendanceHistoryModel? entry =
          _findEntryInWindow(history, window);
      if (entry == null) return null;

      final bool hasCheckIn =
          entry.checkTime != null && entry.checkTime!.year != 1900;
      final bool hasCheckOut =
          entry.checkOutTime != null && entry.checkOutTime!.year != 1900;

      if (hasCheckIn && !hasCheckOut) {
        return CheckStatusModel(
          status: 'checkin',
          latestPunchTime: entry.checkTime!.toIso8601String(),
          punchDate: entry.punchDate?.toIso8601String(),
          id: '',
          checkedInForShift: true,
        );
      }
      if (hasCheckOut) {
        return CheckStatusModel(
          status: 'checkout',
          latestPunchTime: entry.checkOutTime!.toIso8601String(),
          punchDate: entry.punchDate?.toIso8601String(),
          id: '',
          checkedInForShift: hasCheckIn,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OfflineServices] ⚠️ History read error: $e');
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Finds the attendance history entry whose punchDate or checkTime/checkOutTime
  /// falls within [window].
  static AttendanceHistoryModel? _findEntryInWindow(
    List<AttendanceHistoryModel> history,
    ShiftWindow window,
  ) {
    final DateTime windowDay = ShiftWindowCalculator.shiftDay(window);
    for (final entry in history) {
      final pd = entry.punchDate;
      if (pd != null &&
          pd.year == windowDay.year &&
          pd.month == windowDay.month &&
          pd.day == windowDay.day) {
        return entry;
      }
      final ct = entry.checkTime;
      if (ct != null && ShiftWindowCalculator.isInWindow(ct, window)) {
        return entry;
      }
      final cot = entry.checkOutTime;
      if (cot != null && ShiftWindowCalculator.isInWindow(cot, window)) {
        return entry;
      }
    }
    return null;
  }

  static CheckStatusModel _buildStatus(String status, DateTime now) =>
      CheckStatusModel(
        status: status,
        latestPunchTime: now.toIso8601String(),
        punchDate: now.toIso8601String(),
        id: '',
        checkedInForShift: status == 'checkin',
      );

  // ─────────────────────────────────────────────────────────────────────────
  // After offline punch: update cached attendance history & derived status
  // ─────────────────────────────────────────────────────────────────────────

  /// Updates the cached attendance history list for [employeeNo] inside the
  /// active shift window (exact mirror of Timetick's updateCachedHistory).
  ///
  /// - Check-in: updates window entry's checkTime to [punchTime], clears checkOutTime.
  /// - Check-out: updates window entry's checkOutTime to [punchTime].
  /// - If no entry exists in window: creates a new entry and prepends it.
  static Future<void> updateCachedHistory({
    required String employeeNo,
    required String checkType,
    required DateTime punchTime,
    ShiftModel? shift,
  }) async {
    try {
      final ShiftModel? resolvedShift =
          shift ?? await OfflineCacheService.getShift(employeeNo);
      final ShiftWindow window = ShiftWindowCalculator.resolveActiveWindow(
        shift: resolvedShift,
        at: punchTime,
      );

      final List<AttendanceHistoryModel> historyList =
          List.from(await OfflineCacheService.getHistory(employeeNo));

      final upper = checkType.toUpperCase();
      final bool isCheckIn = upper.contains('IN') && !upper.contains('OUT');

      final int index = historyList.indexWhere(
        (entry) => _findEntryInWindow([entry], window) != null,
      );

      if (index != -1) {
        final existing = historyList[index];
        if (isCheckIn) {
          historyList[index] = existing.copyWith(
            checkTime: punchTime,
            clearCheckOutTime: true,
          );
        } else {
          historyList[index] = existing.copyWith(
            checkOutTime: punchTime,
          );
        }
      } else {
        final DateTime shiftDay = ShiftWindowCalculator.shiftDay(window);
        final newEntry = AttendanceHistoryModel(
          employeeNo: employeeNo,
          transactionId: punchTime.millisecondsSinceEpoch,
          punchDate: shiftDay,
          checkTime: isCheckIn ? punchTime : null,
          checkOutTime: isCheckIn ? null : punchTime,
        );
        historyList.insert(0, newEntry);
      }

      await OfflineCacheService.cacheHistory(employeeNo, historyList);
      if (kDebugMode) {
        print(
          '[OfflineServices] ✅ Cached history updated for $employeeNo '
          '(isCheckIn=$isCheckIn, window=${window.source}, total=${historyList.length})',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OfflineServices] ⚠️ Error updating cached history: $e');
      }
    }
  }

  /// Call immediately after [OfflinePunchStore.storePunch] so both the
  /// attendance history list and the quick-lookup derived status reflect the new punch.
  static Future<void> updateCachedStatusAfterPunch({
    required String employeeNo,
    required String checkType,
    required DateTime punchTime,
    ShiftModel? shift,
  }) async {
    // 1. Update the cached attendance history list (same as Timetick)
    await updateCachedHistory(
      employeeNo: employeeNo,
      checkType: checkType,
      punchTime: punchTime,
      shift: shift,
    );

    // 2. Update the quick-lookup derived check status
    final upper = checkType.toUpperCase();
    final String nextStatus =
        upper.contains('OUT') ? 'checkout' : 'checkin';
    await OfflineCacheService.cacheCheckStatus(
      employeeNo,
      CheckStatusModel(
        status: nextStatus,
        latestPunchTime: punchTime.toIso8601String(),
        punchDate: punchTime.toIso8601String(),
        id: '',
        checkedInForShift: nextStatus == 'checkin',
      ),
    );
  }
}
