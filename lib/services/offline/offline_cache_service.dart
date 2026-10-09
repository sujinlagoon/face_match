import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/attendance_history_model.dart';
import '../../data/models/shift_model.dart';
import '../../main_screens/model/checkstatus_model.dart';
import '../../main_screens/model/profile_face_model.dart';

/// Thin SharedPreferences read/write layer. No business logic.
///
/// Keys:
///   `attendance_history_<employeeNo>`  → JSON array of AttendanceHistoryModel
///   `check_status_<employeeNo>`        → JSON object of CheckStatusModel
///   `employee_list`                    → JSON array of EmployeeModel
class OfflineCacheService {
  OfflineCacheService._();

  // ─────────────────────────────────────────────────────────────────────────
  // Attendance History
  // ─────────────────────────────────────────────────────────────────────────

  static String _historyKey(String employeeNo) =>
      'attendance_history_$employeeNo';

  static Future<void> cacheHistory(
    String employeeNo,
    List<AttendanceHistoryModel> list,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey(employeeNo),
        AttendanceHistoryModel.listToJson(list),
      );
      if (kDebugMode) {
        print('[OfflineCacheService] ✅ History cached for $employeeNo (${list.length} records)');
      }
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ cacheHistory error: $e');
    }
  }

  static Future<List<AttendanceHistoryModel>> getHistory(
      String employeeNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey(employeeNo));
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((j) => AttendanceHistoryModel.fromJson(j, employeeNo: employeeNo))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getHistory error: $e');
      return [];
    }
  }

  static Future<void> clearHistory(String employeeNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey(employeeNo));
  }

  /// Returns a map of employeeNo -> List of [AttendanceHistoryModel] for all attendance histories cached locally.
  static Future<Map<String, List<AttendanceHistoryModel>>> getAllCachedHistories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('attendance_history_'));
      final Map<String, List<AttendanceHistoryModel>> map = {};
      for (final key in keys) {
        final empId = key.substring('attendance_history_'.length);
        if (empId == '0' || empId == '1') {
          await prefs.remove(key);
          continue;
        }
        final raw = prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw) as List<dynamic>;
            final list = decoded
                .whereType<Map<String, dynamic>>()
                .map((j) => AttendanceHistoryModel.fromJson(j, employeeNo: empId))
                .toList();
            map[empId] = list;
          } catch (_) {}
        }
      }
      return map;
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getAllCachedHistories error: $e');
      return {};
    }
  }

  /// Clears all cached attendance histories from SharedPreferences.
  static Future<void> clearAllHistories() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('attendance_history_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (kDebugMode) print('[OfflineCacheService] 🧹 Cleared ${keys.length} cached attendance histories');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Derived Check Status
  // ─────────────────────────────────────────────────────────────────────────

  static String _statusKey(String employeeNo) => 'check_status_$employeeNo';

  static Future<void> cacheCheckStatus(
    String employeeNo,
    CheckStatusModel status,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statusKey(employeeNo), jsonEncode(status.toJson()));
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ cacheCheckStatus error: $e');
    }
  }

  static Future<CheckStatusModel?> getCheckStatus(String employeeNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statusKey(employeeNo));
      if (raw == null || raw.isEmpty) return null;
      return CheckStatusModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getCheckStatus error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Employee List (face profiles for 1:N recognition)
  // ─────────────────────────────────────────────────────────────────────────

  static const String _employeeListKey = 'employee_list';

  static Future<void> cacheEmployeeList(List<EmployeeModel> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_employeeListKey, encoded);
      if (kDebugMode) {
        print('[OfflineCacheService] ✅ Employee list cached (${list.length} employees)');
      }
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ cacheEmployeeList error: $e');
    }
  }

  static Future<List<EmployeeModel>> getEmployeeList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_employeeListKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((j) => EmployeeModel.fromJson(j))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getEmployeeList error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shift data (per employee)
  // ─────────────────────────────────────────────────────────────────────────

  static String _shiftKey(String employeeNo) => 'shift_$employeeNo';

  /// Caches the shift for [employeeNo]. Stores only the first shift if list.
  static Future<void> cacheShift(String employeeNo, ShiftModel shift) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_shiftKey(employeeNo), jsonEncode(shift.toJson()));
      if (kDebugMode) {
        print('[OfflineCacheService] ✅ Shift cached for $employeeNo: ${shift.shiftName}');
      }
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ cacheShift error: $e');
    }
  }

  static Future<ShiftModel?> getShift(String employeeNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shiftKey(employeeNo));
      if (raw == null || raw.isEmpty) return null;
      return ShiftModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        employeeNo: employeeNo,
      );
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getShift error: $e');
      return null;
    }
  }

  static Future<void> clearShift(String employeeNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shiftKey(employeeNo));
  }

  /// Returns a map of employeeNo -> ShiftModel for all shifts cached locally.
  static Future<Map<String, ShiftModel>> getAllCachedShifts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('shift_'));
      final Map<String, ShiftModel> map = {};
      for (final key in keys) {
        final empId = key.substring('shift_'.length);
        if (empId == '0' || empId == '1') {
          await prefs.remove(key);
          continue;
        }
        final raw = prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          try {
            final shift = ShiftModel.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
              employeeNo: empId,
            );
            map[empId] = shift;
          } catch (_) {}
        }
      }
      return map;
    } catch (e) {
      if (kDebugMode) print('[OfflineCacheService] ⚠️ getAllCachedShifts error: $e');
      return {};
    }
  }

  /// Clears all cached shifts from SharedPreferences.
  static Future<void> clearAllShifts() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('shift_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (kDebugMode) print('[OfflineCacheService] 🧹 Cleared ${keys.length} cached shifts');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Clear all caches (e.g. on session end)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
          (k) =>
              k.startsWith('attendance_history_') ||
              k.startsWith('check_status_') ||
              k.startsWith('shift_') ||
              k == _employeeListKey,
        );
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (kDebugMode) print('[OfflineCacheService] ✅ All caches cleared');
  }
}
