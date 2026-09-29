class CheckStatusModel {
  String? status;
  String? latestPunchTime;
  String? punchDate;
  String? id;
  bool? checkedInForShift;

  CheckStatusModel({
    this.status,
    this.latestPunchTime,
    this.punchDate,
    this.id,
    this.checkedInForShift,
  });

  factory CheckStatusModel.fromJson(Map<String, dynamic> json) {
    return CheckStatusModel(
      status: json['status'],
      latestPunchTime: json['LatestPunchTime'],
      punchDate: json['PunchDate'],
      id: json['Id'],
      checkedInForShift: json['checked_in_for_shift'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'LatestPunchTime': latestPunchTime,
      'PunchDate': punchDate,
      'Id': id,
      'checked_in_for_shift': checkedInForShift,
    };
  }
}