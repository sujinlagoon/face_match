import '../../main_screens/model/checkstatus_model.dart';
import 'offline_services.dart';

/// Legacy adapter — delegates to [OfflineServices.determineCheckStatus].
/// Kept for backward compatibility.
class OfflineCheckStatusResolver {
  OfflineCheckStatusResolver._();

  /// Delegates to [OfflineServices.determineCheckStatus].
  static Future<CheckStatusModel> resolve(String employeeNo) =>
      OfflineServices.determineCheckStatus(employeeNo);
}


