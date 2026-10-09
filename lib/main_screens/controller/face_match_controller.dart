import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_match/main_screens/model/checkstatus_model.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:ntp/ntp.dart';

import '../../data/models/shift_model.dart';
import '../../data/url.dart';
import '../../helpers/location_service.dart';
import '../../services/face_service/face_matcher_v2.dart';
import '../../services/network/network_controller.dart';
import '../../services/offline/offline_cache_service.dart';
import '../../services/offline/offline_punch_store.dart';
import '../../services/offline/offline_services.dart';
import '../../widgets/custom_toast.dart';
import '../model/profile_face_model.dart';
import '../model/punch_result_model.dart';

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

  PunchFlowResult? lastPunchResult;

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

    // Fast check: if offline, immediately load cached profiles without waiting for timeout
    final bool online = await _isOnline();
    if (!online) {
      final cachedList = await OfflineCacheService.getEmployeeList();
      if (cachedList.isNotEmpty) {
        employeeList = cachedList;
        if (kDebugMode) {
          print(
            "[FaceMatchController] 📴 Offline: Loaded "
            "${employeeList.length} employees with embeddings from local cache",
          );
        }
        isFaceMatch = false;
        update();
        return true;
      }
    }

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
          for (final employee in employeeList) {
            print(
              "[FaceMatchController] "
                  "EmployeeNo: ${employee.employeeNo}, "
                  "MobileCode: ${employee.mobileCode}, "
                  "Name: ${employee.name}",
            );
          }
        }

        // ── Cache employee list for offline 1:N recognition ───────────────
        await OfflineCacheService.cacheEmployeeList(employeeList);

        return true;
      } else {
        // Fallback to offline cache on non-200 response
        final cachedList = await OfflineCacheService.getEmployeeList();
        if (cachedList.isNotEmpty) {
          employeeList = cachedList;
          if (kDebugMode) {
            print(
              "[FaceMatchController] 📴 Non-200 server response (${response.statusCode}), "
              "loaded ${employeeList.length} profiles from local cache",
            );
          }
          return true;
        }

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

      // Fallback to offline cache on network error / timeout
      final cachedList = await OfflineCacheService.getEmployeeList();
      if (cachedList.isNotEmpty) {
        employeeList = cachedList;
        if (kDebugMode) {
          print(
            "[FaceMatchController] 📴 Network error, loaded "
            "${employeeList.length} profiles from offline cache",
          );
        }
        return true;
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

  /// Runs the full check-status → punch flow for a matched employee.
  ///
  /// - When **online**: calls CheckStatus API → newInOut API → caches history.
  /// - When **offline**: resolves status from cached history → stores punch locally.
  ///
  /// Returns [PunchFlowResult] indicating whether the employee checked in or checked out.
  Future<PunchFlowResult> checkStatusForMatchedEmployee(
    EmployeeModel employee, {
    void Function(PunchAction action, bool isOffline)? onStatusResolved,
  }) async {
    // Employee ID = effectiveEmployeeNo (primary: mobileCode, then employeeNo)
    final String empId = employee.effectiveEmployeeNo;

    final String empName = employee.name ?? "Employee";

    print("🔥 checkStatusForMatchedEmployee ENTERED");
    print("🔥 Employee ID (mobileCode/employeeNo): $empId");

    if (empId.isEmpty) {
      print("❌ Employee ID is empty");
      CustomToast.showError("Please check your status");
      return PunchFlowResult(
        success: false,
        timestamp: DateTime.now(),
        message: "Employee ID is empty",
        employeeName: empName,
      );
    }

    // Prevent duplicate calls within the same session
    if (_checkStatusRequestedEmployees.contains(empId)) {
      print("⚠️ CheckStatus already requested for: $empId");
      return lastPunchResult ??
          PunchFlowResult(
            success: true,
            action: null,
            timestamp: DateTime.now(),
            employeeNo: empId,
            employeeName: empName,
          );
    }
    _checkStatusRequestedEmployees.add(empId);

    try {
      // ── Connectivity check ────────────────────────────────────────────────
      final bool online = await _isOnline();
      print("🌐 Network: ${online ? 'ONLINE' : 'OFFLINE'}");

      PunchFlowResult result;
      if (online) {
        result = await _onlinePunchFlow(
          empId,
          empName: empName,
          onStatusResolved: onStatusResolved,
        );
      } else {
        result = await _offlinePunchFlow(
          empId,
          empName: empName,
          onStatusResolved: onStatusResolved,
        );
      }

      lastPunchResult = result;
      update();
      return result;
    } catch (e) {
      print("❌ checkStatusForMatchedEmployee error for $empId: $e");
      CustomToast.showError("Please check your status");
      final failResult = PunchFlowResult(
        success: false,
        timestamp: DateTime.now(),
        employeeNo: empId,
        employeeName: empName,
        message: e.toString(),
      );
      lastPunchResult = failResult;
      update();
      return failResult;
    } finally {
      // Release in-flight lock so subsequent matches can call check status again
      _checkStatusRequestedEmployees.remove(empId);
    }
  }

  // ============================================================
  // ONLINE PUNCH FLOW
  // ============================================================

  Future<PunchFlowResult> _onlinePunchFlow(
    String empId, {
    String? empName,
    void Function(PunchAction action, bool isOffline)? onStatusResolved,
  }) async {
    print("🔥 [ONLINE] Starting online punch flow for $empId");

    // 1. Fetch shift from server and cache it (stores employeeNo on model)
    await _fetchAndCacheShift(empId);
    final ShiftModel? shift = await OfflineCacheService.getShift(empId);

    CheckStatusModel? employeeStatus;

    // 2. Check unsynced local punches first — server doesn't know about them yet (same as Timetick)
    final String? unsyncedStatus = await OfflineServices.resolveFromUnsyncedRecords(
      empId,
      shift: shift,
    );

    if (unsyncedStatus != null) {
      print("⚡ [ONLINE] Preferring unsynced local punch status: $unsyncedStatus for $empId");
      employeeStatus = CheckStatusModel(
        status: unsyncedStatus,
        latestPunchTime: DateTime.now().toIso8601String(),
        punchDate: DateTime.now().toIso8601String(),
        id: '',
        checkedInForShift: unsyncedStatus.toLowerCase() == 'checkin',
      );
    } else {
      // 3. Check Status API — always clear cached status first so we call status API fresh
      employeeCheckStatusMap.remove(empId);
      final bool statusSuccess = await getCheckStatus(empId: empId);
      final List<CheckStatusModel>? statusList = employeeCheckStatusMap[empId];

      if (statusSuccess && statusList != null && statusList.isNotEmpty) {
        employeeStatus = statusList.first;
      } else {
        // Fallback to shift-based OfflineServices resolution
        print("⚠️ [ONLINE] CheckStatus API unavailable, falling back to OfflineServices for $empId");
        employeeStatus = await OfflineServices.determineCheckStatus(empId, shift: shift);
      }
    }

    print("✅ [ONLINE] CHECK STATUS: ${employeeStatus.status} for $empId");

    final String? checkType = _resolveCheckType(employeeStatus.status ?? '');
    final PunchAction action = (checkType != null && checkType.toUpperCase().contains('IN'))
        ? PunchAction.checkIn
        : PunchAction.checkOut;

    // Notify UI that status has been resolved before API call
    onStatusResolved?.call(action, false);

    // 4. newInOut API
    final bool punchSuccess = await newInOut(
      empId: empId,
      checkStatus: employeeStatus,
    );

    if (!punchSuccess) {
      print("⚠️ [ONLINE] Online punch failed for $empId — falling back to offline punch flow");
      return await _offlinePunchFlow(
        empId,
        empName: empName,
        onStatusResolved: onStatusResolved,
      );
    }

    // Punch succeeded: clear cached status map so next match calls status API fresh
    employeeCheckStatusMap.remove(empId);

    print("✅ [ONLINE] Punch success for $empId (${action == PunchAction.checkIn ? 'Check-In' : 'Check-Out'})");

    // 5. Fetch + cache attendance history for future offline use
    await _fetchAndCacheAttendanceHistory(empId);

    return PunchFlowResult(
      success: true,
      action: action,
      isOffline: false,
      timestamp: DateTime.now(),
      employeeNo: empId,
      employeeName: empName,
    );
  }

  // ============================================================
  // OFFLINE PUNCH FLOW
  // ============================================================

  Future<PunchFlowResult> _offlinePunchFlow(
    String empId, {
    String? empName,
    void Function(PunchAction action, bool isOffline)? onStatusResolved,
  }) async {
    print("📴 [OFFLINE] Resolving status from OfflineServices for $empId");

    // 1. Load cached shift (used for shift-window-aware status resolution)
    final shift = await OfflineCacheService.getShift(empId);
    if (shift == null || !shift.hasValidTiming) {
      print("❌ [OFFLINE] Shift not available for $empId — offline check not allowed");
      CustomToast.showError(
        "Shift not available for ${empName ?? 'Employee'}. Offline check not allowed.",
      );
      return PunchFlowResult(
        success: false,
        timestamp: DateTime.now(),
        employeeNo: empId,
        employeeName: empName,
        isOffline: true,
        message: "Shift not available. Offline check not allowed.",
      );
    }

    // 2. Resolve status: unsynced SQLite → cached history → derived cache → default
    final CheckStatusModel offlineStatus =
        await OfflineServices.determineCheckStatus(empId, shift: shift);

    print("📴 [OFFLINE] Resolved status: ${offlineStatus.status}");

    // 3. Map status → check type
    final String? checkType = _resolveCheckType(offlineStatus.status ?? '');
    if (checkType == null) {
      print("❌ [OFFLINE] Unrecognised status: ${offlineStatus.status}");
      CustomToast.showError("Please check your status");
      return PunchFlowResult(
        success: false,
        timestamp: DateTime.now(),
        employeeNo: empId,
        employeeName: empName,
        message: "Unrecognised status: ${offlineStatus.status}",
      );
    }

    final PunchAction action = checkType.toUpperCase().contains('IN')
        ? PunchAction.checkIn
        : PunchAction.checkOut;

    // Notify UI that status has been resolved before local punch store
    onStatusResolved?.call(action, true);

    // 4. Collect location + NTP time + device ID
    LocationDataResult locData;
    try {
      locData = await LocationService.getCurrentLocationData().timeout(
        const Duration(seconds: 4),
        onTimeout: () => const LocationDataResult(
            latitude: '', longitude: '', address: ''),
      );
    } catch (_) {
      locData =
          const LocationDataResult(latitude: '', longitude: '', address: '');
    }

    final DateTime punchTime = await getNtpTime();
    final String deviceId   = await getDeviceId();

    // 5. Store punch locally in SQLite
    await OfflinePunchStore.storePunch(
      employeeNo: empId,
      checkType:  checkType,
      dateTime:   punchTime,
      latitude:   locData.latitude,
      longitude:  locData.longitude,
      location:   locData.address,
      deviceId:   deviceId,
    );

    // 6. Update cached attendance history & derived status so next resolve is correct
    await OfflineServices.updateCachedStatusAfterPunch(
      employeeNo: empId,
      checkType:  checkType,
      punchTime:  punchTime,
      shift:      shift,
    );

    print("✅ [OFFLINE] Punch stored locally: $checkType for $empId (${action == PunchAction.checkIn ? 'Check-In' : 'Check-Out'})");
    if (Get.isRegistered<NetworkController>()) {
      Get.find<NetworkController>().notifyOfflinePunchSaved();
    }
    return PunchFlowResult(
      success: true,
      action: action,
      isOffline: true,
      timestamp: punchTime,
      employeeNo: empId,
      employeeName: empName,
    );
  }

  // ============================================================
  // ATTENDANCE HISTORY — FETCH & CACHE
  // ============================================================

  /// Fetches today's attendance history for [employeeNo] and caches it.
  /// Called after every successful online punch. Non-fatal on failure.
  Future<void> _fetchAndCacheAttendanceHistory(String employeeNo) async {
    try {
      await OfflineServices.fetchAndCacheAttendanceHistory(employeeNo);
    } catch (e) {
      // Non-fatal — the punch already succeeded
      if (kDebugMode) {
        print('[FaceMatchController] ⚠️ History cache skipped: $e');
      }
    }
  }

  // ============================================================
  // SHIFT — FETCH & CACHE
  // ============================================================

  /// Fetches shift from ShiftMasterAPI for [employeeNo] and caches it.
  /// Called at the start of every online punch flow. Non-fatal on failure.
  Future<void> _fetchAndCacheShift(String employeeNo) async {
    try {
      final shift = await OfflineServices.fetchAndCacheShift(employeeNo);
      if (shift != null && kDebugMode) {
        print('[FaceMatchController] ✅ Shift cached for $employeeNo: '
            '${shift.shiftName} (${shift.inTime} – ${shift.outTime})');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FaceMatchController] ⚠️ Shift fetch skipped: $e');
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Returns true when the device has a working API connection.
  Future<bool> _isOnline() async {
    try {
      if (Get.isRegistered<NetworkController>()) {
        return await Get.find<NetworkController>().checkConnectivity();
      }
      // Fallback: quick HTTP ping
      final response = await http
          .get(Uri.parse(Url.healthCheck))
          .timeout(const Duration(seconds: 4));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Maps CheckStatus API status string → platform-specific CheckType string.
  /// Returns null for unrecognised statuses.
  static String? _resolveCheckType(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'checkin') {
      return Platform.isAndroid ? 'Android_Out' : 'IOS_OUT';
    }
    if (s == 'checkout' || s == 'out') {
      return Platform.isAndroid ? 'Android_IN' : 'IN';
    }
    return null;
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
      final String? checkType = _resolveCheckType(checkStatus.status ?? '');
      if (checkType == null) {
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

      final response = await http
          .get(requestUri)
          .timeout(const Duration(seconds: 10));

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