import 'dart:convert';

List<ShiftModel> shiftListFromJson(String str) =>
    List<ShiftModel>.from(json.decode(str).map((x) => ShiftModel.fromJson(x)));

String shiftListToJson(List<ShiftModel> data) =>
    json.encode(data.map((x) => x.toJson()).toList());

/// Employee shift data from ShiftMasterAPI.
///
/// [employeeNo] is injected locally (= mobileCode) before caching so that
/// the 1:N face-match flow can retrieve the right shift per employee.
class ShiftModel {
  /// Employee identifier — injected before caching, not from API body.
  final String? employeeNo;

  final int?    shiftId;
  final String? shiftCode;
  final String? shiftName;
  final String? name;

  /// Shift start time string — ISO datetime or "HH:mm:ss".
  final String? inTime;

  /// Shift end time string — ISO datetime or "HH:mm:ss".
  final String? outTime;

  const ShiftModel({
    this.employeeNo,
    this.shiftId,
    this.shiftCode,
    this.shiftName,
    this.name,
    this.inTime,
    this.outTime,
  });

  factory ShiftModel.fromJson(Map<String, dynamic> json, {String? employeeNo}) =>
      ShiftModel(
        employeeNo: employeeNo ?? json['employeeNo'] as String?,
        shiftId:    json['ShiftID']   as int?,
        shiftCode:  json['ShiftCode'] as String?,
        shiftName:  json['ShiftName'] as String?,
        name:       json['Name']      as String?,
        inTime:     json['InTime']    as String?,
        outTime:    json['OutTime']   as String?,
      );

  Map<String, dynamic> toJson() => {
        'employeeNo': employeeNo,
        'ShiftID':    shiftId,
        'ShiftCode':  shiftCode,
        'ShiftName':  shiftName,
        'Name':       name,
        'InTime':     inTime,
        'OutTime':    outTime,
      };

  // ─────────────────────────────────────────────────────────────────────────
  // List helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Parses server response array and injects [employeeNo] into every record.
  static List<ShiftModel> listFromJson(String rawJson, {required String employeeNo}) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      List<dynamic> rawList = [];
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['data']   is List) rawList = decoded['data']   as List;
        if (decoded['result'] is List) rawList = decoded['result'] as List;
      }
      return rawList
          .whereType<Map<String, dynamic>>()
          .map((j) => ShiftModel.fromJson(j, employeeNo: employeeNo))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the first shift from the list, or null if empty.
  static ShiftModel? firstFromJson(String rawJson, {required String employeeNo}) {
    final list = listFromJson(rawJson, employeeNo: employeeNo);
    return list.isEmpty ? null : list.first;
  }

  @override
  String toString() =>
      'ShiftModel(empNo=$employeeNo, in=$inTime, out=$outTime, name=$shiftName)';
}
