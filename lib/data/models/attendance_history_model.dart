import 'dart:convert';

/// Per-employee attendance history record used by the offline punch system.
///
/// [employeeNo] is the mobileCode used as the cache key — it is NOT part of
/// the API response body; it is injected locally before caching so that the
/// 1:N recognition flow can look up the correct history per employee.
class AttendanceHistoryModel {
  /// The employee identifier (mobileCode). Injected before caching.
  final String? employeeNo;

  final int? transactionId;

  /// First check-in time of this shift window.
  final DateTime? checkTime;

  /// Last check-out time of this shift window (null if still checked in).
  final DateTime? checkOutTime;

  /// Calendar date of this punch session (midnight boundary).
  final DateTime? punchDate;

  const AttendanceHistoryModel({
    this.employeeNo,
    this.transactionId,
    this.checkTime,
    this.checkOutTime,
    this.punchDate,
  });

  factory AttendanceHistoryModel.fromJson(
    Map<String, dynamic> json, {
    String? employeeNo,
  }) {
    return AttendanceHistoryModel(
      employeeNo: employeeNo,
      transactionId: json['TransactionID'] as int?,
      checkTime: _parseDate(json['CheckTime']),
      checkOutTime: _parseDate(json['CheckOutTime']),
      punchDate: _parseDate(json['PunchDate']),
    );
  }

  Map<String, dynamic> toJson() => {
        'employeeNo': employeeNo,
        'TransactionID': transactionId,
        'CheckTime': checkTime?.toIso8601String(),
        'CheckOutTime': checkOutTime?.toIso8601String(),
        'PunchDate': punchDate?.toIso8601String(),
      };

  AttendanceHistoryModel copyWith({
    String? employeeNo,
    int? transactionId,
    DateTime? checkTime,
    DateTime? checkOutTime,
    bool clearCheckOutTime = false,
    DateTime? punchDate,
  }) {
    return AttendanceHistoryModel(
      employeeNo: employeeNo ?? this.employeeNo,
      transactionId: transactionId ?? this.transactionId,
      checkTime: checkTime ?? this.checkTime,
      checkOutTime:
          clearCheckOutTime ? null : (checkOutTime ?? this.checkOutTime),
      punchDate: punchDate ?? this.punchDate,
    );
  }

  /// Parses server JSON array and injects [employeeNo] into every record.
  static List<AttendanceHistoryModel> listFromJson(
    String rawJson, {
    required String employeeNo,
  }) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      List<dynamic> rawList = [];
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is List) rawList = decoded['data'] as List;
        if (decoded['result'] is List) rawList = decoded['result'] as List;
      }
      return rawList
          .whereType<Map<String, dynamic>>()
          .map((item) => AttendanceHistoryModel.fromJson(item, employeeNo: employeeNo))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<AttendanceHistoryModel> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  @override
  String toString() =>
      'AttendanceHistoryModel(empNo=$employeeNo, checkTime=$checkTime, checkOutTime=$checkOutTime)';
}
