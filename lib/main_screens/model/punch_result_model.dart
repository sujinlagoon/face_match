enum PunchAction {
  checkIn,
  checkOut,
}

class PunchFlowResult {
  final bool success;
  final PunchAction? action;
  final bool isOffline;
  final DateTime timestamp;
  final String? employeeNo;
  final String? employeeName;
  final String? message;

  const PunchFlowResult({
    required this.success,
    this.action,
    this.isOffline = false,
    required this.timestamp,
    this.employeeNo,
    this.employeeName,
    this.message,
  });

  String get actionLabel =>
      action == PunchAction.checkIn ? "Checked In" : "Checked Out";

  String get shortAction =>
      action == PunchAction.checkIn ? "Check-In" : "Check-Out";

  String get formattedTime {
    final hour =
        timestamp.hour > 12 ? timestamp.hour - 12 : (timestamp.hour == 0 ? 12 : timestamp.hour);
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute:$second $period';
  }
}
