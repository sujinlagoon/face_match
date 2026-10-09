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

  final int? shiftId;
  final String? shiftCode;
  final String? shiftName;
  final String? name;

  /// Shift start time string — ISO datetime or "HH:mm:ss".
  final String? inTime;

  /// Shift end time string — ISO datetime or "HH:mm:ss".
  final String? outTime;

  /// Pre-shift early arrival buffer in minutes (default: 60 minutes = 1 hour).
  final int? preShiftBufferMinutes;

  /// Post-shift overtime/late checkout buffer in minutes (default: 480 minutes = 8 hours).
  final int? postShiftBufferMinutes;

  /// Policy: whether early check-in before shift start time is allowed (default: true).
  final bool allowPreShiftCheckIn;

  /// Policy: whether late check-out after shift end time is allowed (default: true).
  final bool allowPostShiftCheckOut;

  const ShiftModel({
    this.employeeNo,
    this.shiftId,
    this.shiftCode,
    this.shiftName,
    this.name,
    this.inTime,
    this.outTime,
    this.preShiftBufferMinutes,
    this.postShiftBufferMinutes,
    this.allowPreShiftCheckIn = true,
    this.allowPostShiftCheckOut = true,
  });

  /// Duration getter for pre-shift buffer (defaults to 1 hour / 60 minutes).
  Duration get preShiftBuffer =>
      Duration(minutes: preShiftBufferMinutes ?? 60);

  /// Duration getter for post-shift buffer (defaults to 8 hours / 480 minutes).
  Duration get postShiftBuffer =>
      Duration(minutes: postShiftBufferMinutes ?? 480);

  /// Returns true if shift has valid inTime and outTime timings.
  bool get hasValidTiming =>
      inTime != null &&
      inTime!.trim().isNotEmpty &&
      outTime != null &&
      outTime!.trim().isNotEmpty;

  factory ShiftModel.fromJson(Map<String, dynamic> json, {String? employeeNo}) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool parseBool(dynamic v, {bool defaultValue = true}) {
      if (v == null) return defaultValue;
      if (v is bool) return v;
      if (v is num) return v == 1;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return defaultValue;
    }

    return ShiftModel(
      employeeNo: employeeNo ?? json['employeeNo'] as String?,
      shiftId: parseInt(json['ShiftID'] ?? json['shiftId']),
      shiftCode: (json['ShiftCode'] ?? json['shiftCode']) as String?,
      shiftName: (json['ShiftName'] ?? json['shiftName']) as String?,
      name: (json['Name'] ?? json['name']) as String?,
      inTime: (json['InTime'] ?? json['inTime']) as String?,
      outTime: (json['OutTime'] ?? json['outTime']) as String?,
      preShiftBufferMinutes: parseInt(
        json['PreShiftBufferMinutes'] ??
            json['preShiftBufferMinutes'] ??
            json['PreShiftBuffer'] ??
            json['preShiftBuffer'] ??
            json['EarlyArrivalMinutes'],
      ),
      postShiftBufferMinutes: parseInt(
        json['PostShiftBufferMinutes'] ??
            json['postShiftBufferMinutes'] ??
            json['PostShiftBuffer'] ??
            json['postShiftBuffer'] ??
            json['LateCheckoutMinutes'],
      ),
      allowPreShiftCheckIn: parseBool(
        json['AllowPreShiftCheckIn'] ??
            json['allowPreShiftCheckIn'] ??
            json['AllowPreShiftCheck'] ??
            json['allowPreShiftCheck'],
        defaultValue: true,
      ),
      allowPostShiftCheckOut: parseBool(
        json['AllowPostShiftCheckOut'] ??
            json['allowPostShiftCheckOut'] ??
            json['AllowPostShiftCheck'] ??
            json['allowPostShiftCheck'],
        defaultValue: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'employeeNo': employeeNo,
        'ShiftID': shiftId,
        'ShiftCode': shiftCode,
        'ShiftName': shiftName,
        'Name': name,
        'InTime': inTime,
        'OutTime': outTime,
        'PreShiftBufferMinutes': preShiftBufferMinutes ?? 60,
        'PostShiftBufferMinutes': postShiftBufferMinutes ?? 480,
        'AllowPreShiftCheckIn': allowPreShiftCheckIn,
        'AllowPostShiftCheckOut': allowPostShiftCheckOut,
      };

  ShiftModel copyWith({
    String? employeeNo,
    int? shiftId,
    String? shiftCode,
    String? shiftName,
    String? name,
    String? inTime,
    String? outTime,
    int? preShiftBufferMinutes,
    int? postShiftBufferMinutes,
    bool? allowPreShiftCheckIn,
    bool? allowPostShiftCheckOut,
  }) =>
      ShiftModel(
        employeeNo: employeeNo ?? this.employeeNo,
        shiftId: shiftId ?? this.shiftId,
        shiftCode: shiftCode ?? this.shiftCode,
        shiftName: shiftName ?? this.shiftName,
        name: name ?? this.name,
        inTime: inTime ?? this.inTime,
        outTime: outTime ?? this.outTime,
        preShiftBufferMinutes:
            preShiftBufferMinutes ?? this.preShiftBufferMinutes,
        postShiftBufferMinutes:
            postShiftBufferMinutes ?? this.postShiftBufferMinutes,
        allowPreShiftCheckIn:
            allowPreShiftCheckIn ?? this.allowPreShiftCheckIn,
        allowPostShiftCheckOut:
            allowPostShiftCheckOut ?? this.allowPostShiftCheckOut,
      );

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
        if (decoded['data'] is List) rawList = decoded['data'] as List;
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
      'ShiftModel(empNo=$employeeNo, in=$inTime, out=$outTime, preBuffer=${preShiftBuffer.inMinutes}m, postBuffer=${postShiftBuffer.inMinutes}m, allowPreCheckIn=$allowPreShiftCheckIn, allowPostCheckOut=$allowPostShiftCheckOut)';
}
