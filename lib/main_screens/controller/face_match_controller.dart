import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_match/main_screens/model/checkstatus_model.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:ntp/ntp.dart';

import '../../data/url.dart';
import '../../helpers/location_service.dart';
import '../../services/face_service/face_matcher_v2.dart';
import '../../widgets/custom_toast.dart';
import '../model/profile_face_model.dart';

class FaceMatchMatchResult {
  final EmployeeModel employee;
  final double similarity;

  const FaceMatchMatchResult({
    required this.employee,
    required this.similarity,
  });
}

class FaceMatchController extends GetxController {
  bool isFaceMatch = false;
  String? errorMessage;

  List<EmployeeModel> employeeList = [];

  // ============================================================
  // CHECK STATUS
  // ============================================================

  List<CheckStatusModel>? checkStatusModel;

  /// EmployeeNo -> CheckStatus list
  final Map<String, List<CheckStatusModel>> employeeCheckStatusMap = {};

  /// Prevent duplicate CheckStatus API calls
  /// for the same employee during the current camera session.
  final Set<String> _checkStatusRequestedEmployees = {};

  // ============================================================
  // FACE MATCH API
  // ============================================================

  /// Fetch registered employee face profiles
  Future<bool> faceMatchApi({String? timeKeeperId}) async {
    isFaceMatch = true;
    errorMessage = null;
    update();

    try {
      final uri = Uri.parse(
        '${Url.faceMatch}?EmployeeNo=${timeKeeperId ?? ''}',
      );

      if (kDebugMode) {
        print(
          "[FaceMatchController] Fetching face profiles from: $uri",
        );
      }

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        print(
          "[FaceMatchController] Status: ${response.statusCode}",
        );
      }

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);

        List<dynamic> rawList = [];

        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          if (decoded['data'] is List) {
            rawList = decoded['data'];
          } else if (decoded['result'] is List) {
            rawList = decoded['result'];
          } else if (decoded['EmployeeList'] is List) {
            rawList = decoded['EmployeeList'];
          }
        }

        final parsedList = rawList
            .map(
              (item) => EmployeeModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
            .toList();

        // Keep only employees with valid face embeddings
        employeeList = parsedList
            .where(
              (emp) =>
          emp.faceEmbedding != null &&
              emp.faceEmbedding!.isNotEmpty,
        )
            .toList();

        if (kDebugMode) {
          print(
            "[FaceMatchController] Loaded "
                "${employeeList.length} employees with embeddings "
                "(total received: ${parsedList.length})",
          );

          // Debug employee information
          for (final employee in employeeList) {
            print(
              "[FaceMatchController] "
                  "EmployeeNo: ${employee.employeeNo}, "
                  "MobileCode: ${employee.mobileCode}, "
                  "Name: ${employee.name}",
            );
          }
        }

        return true;
      } else {
        errorMessage =
        "Server returned status ${response.statusCode}";
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          "[FaceMatchController] Error fetching face profiles: $e",
        );
      }

      errorMessage = e.toString();
      return false;
    } finally {
      isFaceMatch = false;
      update();
    }
  }

  // ============================================================
  // 1:N FACE MATCHING
  // ============================================================

  FaceMatchMatchResult? matchLiveEmbedding(
      List<double> liveEmbedding, {
        double threshold =
            FaceMatcherV2.defaultSimilarityThreshold,
      }) {
    if (employeeList.isEmpty || liveEmbedding.isEmpty) {
      return null;
    }

    EmployeeModel? bestEmployee;
    double highestSimilarity = -1.0;

    for (final employee in employeeList) {
      final storedEmbedding = employee.faceEmbedding;

      if (storedEmbedding == null ||
          storedEmbedding.isEmpty) {
        continue;
      }

      final similarity = FaceMatcherV2.cosineSimilarity(
        liveEmbedding,
        storedEmbedding,
      );

      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        bestEmployee = employee;
      }
    }

    if (bestEmployee != null &&
        highestSimilarity >= threshold) {
      return FaceMatchMatchResult(
        employee: bestEmployee,
        similarity: highestSimilarity,
      );
    }

    return null;
  }

  // ============================================================
  // CHECK STATUS API
  // ============================================================

  Future<bool> getCheckStatus({
    String? empId,
  }) async {
    if (empId == null || empId.isEmpty) {
      if (kDebugMode) {
        print(
          "[FaceMatchController] CheckStatus skipped: Employee ID is empty",
        );
      }

      return false;
    }

    try {
      final uri = Uri.parse("${Url.checkStatus}?EmployeeNo=$empId",);

      if (kDebugMode) {
        print("[FaceMatchController] CheckStatus API: $uri",);
      }

      final result = await http.get(uri).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print("[FaceMatchController] CheckStatus ""EmployeeNo: $empId ""Status: ${result.statusCode}",);

        print("[FaceMatchController] Response: ${result.body}",);
      }

      // ==========================================================
      // NON 200
      // ==========================================================

      if (result.statusCode != 200) {
        if (kDebugMode) {
          print("[FaceMatchController] CheckStatus failed ""for $empId: ${result.statusCode}",);
        }
        return false;
      }

      // ==========================================================
      // PARSE RESPONSE
      // ==========================================================

      final dynamic decoded = jsonDecode(result.body);

      List<dynamic> rawList = [];

      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is List) {
          rawList = decoded['data'];
        } else if (decoded['result'] is List) {
          rawList = decoded['result'];
        } else {
          rawList = [decoded];
        }
      }

      // ==========================================================
      // EMPTY RESPONSE
      // ==========================================================

      if (rawList.isEmpty) {
        if (kDebugMode) {
          print("[FaceMatchController] CheckStatus returned EMPTY ""for EmployeeNo: $empId",
          );
        }

        return false;
      }

      // ==========================================================
      // PARSE MODEL
      // ==========================================================

      final parsedList = rawList.whereType<Map<String, dynamic>>().map((item) => CheckStatusModel.fromJson(item),
      ).toList();

      // Model parsing produced nothing
      if (parsedList.isEmpty) {
        if (kDebugMode) {
          print("[FaceMatchController] CheckStatus parsed list EMPTY ""for EmployeeNo: $empId",);
        }
        return false;
      }

      // ==========================================================
      // SAVE STATUS
      // ==========================================================

      checkStatusModel = parsedList;

      employeeCheckStatusMap[empId] = parsedList;

      if (kDebugMode) {
        print(
          "[FaceMatchController] CheckStatus saved "
              "for EmployeeNo: $empId",
        );

        for (final status in parsedList) {
          print(
            "[FaceMatchController] "
                "EmployeeNo: $empId | "
                "Status: ${status.status} | "
                "LatestPunchTime: ${status.latestPunchTime} | "
                "PunchDate: ${status.punchDate} | "
                "CheckedInForShift: ${status.checkedInForShift}",
          );
        }
      }

      update();

      return true;
    } catch (e) {
      if (kDebugMode) {
        print(
          "[FaceMatchController] CheckStatus error "
              "for $empId: $e",
        );
      }

      return false;
    }
  }
  // ============================================================
  // CHECK STATUS FOR MATCHED EMPLOYEE
  // ============================================================

  /// Calls CheckStatus API only once for each employee
  /// during the current face recognition session.
  Future<bool> checkStatusForMatchedEmployee(
      EmployeeModel employee,
      ) async {
    // IMPORTANT:
    // In this project, Employee ID comes from mobileCode
    final String? empId = employee.mobileCode;

    print("🔥 checkStatusForMatchedEmployee ENTERED");
    print("🔥 Employee ID (mobileCode): $empId");

    if (empId == null || empId.isEmpty) {
      print("❌ Employee ID is empty");

      CustomToast.showError(
        "Please check your status",
      );

      return false;
    }

    // Prevent duplicate CheckStatus API call
    if (_checkStatusRequestedEmployees.contains(empId)) {
      print("⚠️ CheckStatus already requested for: $empId");
      return true;
    }

    _checkStatusRequestedEmployees.add(empId);

    try {
      // ==========================================
      // 1. CHECK STATUS API
      // ==========================================

      print("🔥 CALLING CHECK STATUS API: $empId");

      final bool statusSuccess = await getCheckStatus(
        empId: empId,
      );

      print("🔥 CHECK STATUS RESULT: $statusSuccess");

      // ==========================================
      // 2. API FAILED / EMPTY
      // ==========================================

      if (!statusSuccess) {
        print("❌ CheckStatus failed/empty: $empId");

        CustomToast.showError(
          "Please check your status",
        );

        _checkStatusRequestedEmployees.remove(empId);

        return false;
      }

      // ==========================================
      // 3. GET THIS EMPLOYEE'S STATUS
      // ==========================================

      final List<CheckStatusModel>? statusList =
      employeeCheckStatusMap[empId];

      if (statusList == null || statusList.isEmpty) {
        print("❌ No CheckStatus data for: $empId");

        CustomToast.showError(
          "Please check your status",
        );

        _checkStatusRequestedEmployees.remove(empId);

        return false;
      }

      final CheckStatusModel employeeStatus =
          statusList.first;

      print(
        "✅ CHECK STATUS FOUND\n"
            "Employee ID: $empId\n"
            "Status: ${employeeStatus.status}",
      );

      // ==========================================
      // 4. NEW IN OUT
      // ==========================================

      final bool punchSuccess = await newInOut(
        empId: empId,
        checkStatus: employeeStatus,
      );

      print(
        "🔥 NEW IN OUT RESULT: ""$empId -> $punchSuccess -->$employeeStatus",
      );

      if (!punchSuccess) {
        _checkStatusRequestedEmployees.remove(empId);

        CustomToast.showError(
          "Unable to update your status",
        );

        return false;
      }

      return true;
    } catch (e) {
      print(
        "❌ CheckStatus flow error for $empId: $e",
      );

      _checkStatusRequestedEmployees.remove(empId);

      CustomToast.showError(
        "Please check your status",
      );

      return false;
    }
  }  // ============================================================
  // CLEAR SESSION
  // ============================================================

  /// Call this when starting a new face recognition session.
  void clearCheckStatusSession() {
    _checkStatusRequestedEmployees.clear();
    employeeCheckStatusMap.clear();
    checkStatusModel = null;

    if (kDebugMode) {
      print(
        "[FaceMatchController] CheckStatus session cleared",
      );
    }

    update();
  }
  Future<DateTime> getNtpTime() async {
    try {
      final DateTime ntpTime = await NTP.now().timeout(
        const Duration(seconds: 3),
        onTimeout: () => DateTime.now(),
      );

      if (kDebugMode) {
        print(
          "[FaceMatchController] NTP Time: $ntpTime",
        );
      }

      return ntpTime;
    } catch (e) {
      if (kDebugMode) {
        print(
          "[FaceMatchController] NTP Time Error: $e",
        );
      }

      return DateTime.now();
    }
  }

  Future<String> getDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo =
        await deviceInfo.androidInfo;

        if (kDebugMode) {
          print(
            "[FaceMatchController] Android Device ID: ""${androidInfo.id}",
          );
        }

        return androidInfo.id;
      }

      if (Platform.isIOS) {
        final IosDeviceInfo iosInfo =
        await deviceInfo.iosInfo;

        if (kDebugMode) {
          print(
            "[FaceMatchController] iOS Device ID: "
                "${iosInfo.identifierForVendor}",
          );
        }

        return iosInfo.identifierForVendor ?? "";
      }

      return "";
    } catch (e) {
      if (kDebugMode) {
        print(
          "[FaceMatchController] Device ID Error: $e",
        );
      }

      return "";
    }
  }

  Future<bool> newInOut({
    required String empId,
    required CheckStatusModel checkStatus,
  }) async {
    try {
      String checkType = "NA";

      final String status =
          checkStatus.status?.trim().toLowerCase() ?? "";

      // CheckStatus API:
      // checkin -> punch API checkout
      // out     -> punch API in
      if (status == "checkin") {
        if (Platform.isAndroid) {
          checkType = "Android_Out";
        } else if (Platform.isIOS) {
          checkType = "IOS_OUT";
        }
      } else if (status == "checkout" || status == "out") {
        if (Platform.isAndroid) {
          checkType = "Android_IN";
        } else if (Platform.isIOS) {
          checkType = "IN";
        }
      } else {
        CustomToast.showError("Please check your status");
        return false;
      }

      // -----------------------------
      // Current Location
      // -----------------------------
      LocationDataResult locData;

      try {
        locData = await LocationService.getCurrentLocationData().timeout(
          const Duration(seconds: 4),
          onTimeout: () => const LocationDataResult(
            latitude: '',
            longitude: '',
            address: '',
          ),
        );
      } catch (_) {
        locData = const LocationDataResult(
          latitude: '',
          longitude: '',
          address: '',
        );
      }

      final String latitude = locData.latitude;
      final String longitude = locData.longitude;
      final String location = locData.address;

      // -----------------------------
      // Google / NTP Time
      // -----------------------------
      final DateTime ntpTime = await getNtpTime();

      // -----------------------------
      // Device ID
      // -----------------------------
      final String deviceId = await getDeviceId();

      // -----------------------------
      // Request Parameters
      // -----------------------------
      final Map<String, String> params = {
        'Latitude': latitude,
        'Longitude': longitude,
        'CheckType': checkType,
        'CheckTime': ntpTime.toString(),
        'Location': location,
        'Device': deviceId,
        'ProjectId': "",
        'GeoId': '',
        'GeoLocationnName': location,
      };

      final String url = '${Url.newCheckInURL}$empId';

      print("🚀 EMPLOYEE ID: $empId");
      print("🚀 CHECK STATUS: ${checkStatus.status}");
      print("🚀 CHECK TYPE: $checkType");
      print("🚀 NTP TIME: $ntpTime");
      print("🚀 LATITUDE: $latitude");
      print("🚀 LONGITUDE: $longitude");
      print("🚀 LOCATION: $location");
      print("🚀 DEVICE ID: $deviceId");
      print("🚀 PUNCH REQUEST PARAMS: $params");

      // http.get does NOT support params:
      // Build query parameters into URI.
      final Uri requestUri = Uri.parse(url).replace(
        queryParameters: params,
      );

      print("🚀 FULL PUNCH URL: $requestUri");

      final response = await http.get(requestUri);

      if (response.statusCode == 200) {
        print("✅ PUNCH SUCCESS: $empId");

        return true;
      } else {
        log(
          "Error in newInOut response ${response.statusCode}",
        );

        print("❌ PUNCH FAILED: ${response.body}");

        return false;
      }
    } catch (e) {
      log("newInOut error: $e");

      return false;
    }
  }
}