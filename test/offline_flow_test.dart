import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:face_match/data/models/attendance_history_model.dart';
import 'package:face_match/data/models/shift_model.dart';
import 'package:face_match/main_screens/model/checkstatus_model.dart';
import 'package:face_match/main_screens/model/profile_face_model.dart';
import 'package:face_match/services/offline/offline_cache_service.dart';
import 'package:face_match/services/offline/offline_services.dart';
import 'package:face_match/services/offline/shift/shift_window_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShiftWindowCalculator Tests', () {
    test('Standard Day Shift (09:00 - 18:00)', () {
      const shift = ShiftModel(
        employeeNo: 'EMP001',
        shiftName: 'General Shift',
        inTime: '09:00:00',
        outTime: '18:00:00',
      );

      final testTime = DateTime(2026, 10, 6, 12, 0); // 12:00 PM
      final window = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: testTime,
      );

      // Buffer: 09:00 - 1h = 08:00, 18:00 + 8h = 02:00 next day
      expect(window.start, DateTime(2026, 10, 6, 8, 0));
      expect(window.end, DateTime(2026, 10, 7, 2, 0));
      expect(window.overnight, isFalse);
      expect(window.contains(testTime), isTrue);
      expect(window.contains(DateTime(2026, 10, 6, 7, 59)), isFalse);
      expect(window.contains(DateTime(2026, 10, 7, 1, 59)), isTrue);
    });

    test('Overnight Shift (22:00 - 06:00)', () {
      const shift = ShiftModel(
        employeeNo: 'EMP002',
        shiftName: 'Night Shift',
        inTime: '22:00:00',
        outTime: '06:00:00',
      );

      // Punching at 23:30 (Day 1)
      final testTime1 = DateTime(2026, 10, 6, 23, 30);
      final window1 = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: testTime1,
      );
      expect(window1.overnight, isTrue);
      expect(window1.contains(testTime1), isTrue);

      // Punching at 05:00 (Day 2 morning - belongs to Day 1 overnight shift)
      final testTime2 = DateTime(2026, 10, 7, 5, 0);
      final window2 = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: testTime2,
      );
      expect(window2.contains(testTime2), isTrue);
    });

    test('Null Shift falls back to calendar day', () {
      final now = DateTime(2026, 10, 6, 15, 30);
      final window = ShiftWindowCalculator.resolveActiveWindow(
        shift: null,
        at: now,
      );

      expect(window.start, DateTime(2026, 10, 6, 0, 0));
      expect(window.end, DateTime(2026, 10, 7, 0, 0));
      expect(window.source, 'calendar_day');
      expect(window.contains(now), isTrue);
    });

    test('Custom Shift Buffers (30 min pre, 120 min post)', () {
      const shift = ShiftModel(
        employeeNo: 'EMP003',
        shiftName: 'Custom Buffer Shift',
        inTime: '09:00:00',
        outTime: '17:00:00',
        preShiftBufferMinutes: 30,
        postShiftBufferMinutes: 120,
      );

      final window = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: DateTime(2026, 10, 6, 10, 0),
      );

      // Buffer: 09:00 - 30m = 08:30, 17:00 + 2h = 19:00
      expect(window.start, DateTime(2026, 10, 6, 8, 30));
      expect(window.end, DateTime(2026, 10, 6, 19, 0));
      expect(window.contains(DateTime(2026, 10, 6, 8, 29)), isFalse);
      expect(window.contains(DateTime(2026, 10, 6, 8, 30)), isTrue);
      expect(window.contains(DateTime(2026, 10, 6, 19, 0)), isFalse);
    });

    test('Policy: Disallow pre-shift check-in (allowPreShiftCheckIn = false)', () {
      const shift = ShiftModel(
        employeeNo: 'EMP004',
        shiftName: 'Strict Arrival Shift',
        inTime: '09:00:00',
        outTime: '17:00:00',
        allowPreShiftCheckIn: false,
        preShiftBufferMinutes: 60,
      );

      final window = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: DateTime(2026, 10, 6, 10, 0),
      );

      // Window starts strictly at shiftIn (09:00), no pre-buffer allowed
      expect(window.start, DateTime(2026, 10, 6, 9, 0));
      expect(window.contains(DateTime(2026, 10, 6, 8, 59)), isFalse);
      expect(window.contains(DateTime(2026, 10, 6, 9, 0)), isTrue);
    });

    test('Policy: Disallow post-shift check-out (allowPostShiftCheckOut = false)', () {
      const shift = ShiftModel(
        employeeNo: 'EMP005',
        shiftName: 'Strict Checkout Shift',
        inTime: '09:00:00',
        outTime: '17:00:00',
        allowPostShiftCheckOut: false,
        postShiftBufferMinutes: 480,
      );

      final window = ShiftWindowCalculator.resolveActiveWindow(
        shift: shift,
        at: DateTime(2026, 10, 6, 10, 0),
      );

      // Window ends strictly at shiftOut (17:00), no post-buffer allowed
      expect(window.end, DateTime(2026, 10, 6, 17, 0));
      expect(window.contains(DateTime(2026, 10, 6, 16, 59)), isTrue);
      expect(window.contains(DateTime(2026, 10, 6, 17, 0)), isFalse);
    });

    test('ShiftModel JSON serialization preserves buffer and policy fields', () {
      final json = {
        'employeeNo': 'EMP006',
        'ShiftID': 42,
        'ShiftCode': 'SH01',
        'ShiftName': 'Flex Shift',
        'InTime': '08:30:00',
        'OutTime': '17:30:00',
        'PreShiftBufferMinutes': 45,
        'PostShiftBufferMinutes': 180,
        'AllowPreShiftCheckIn': true,
        'AllowPostShiftCheckOut': false,
      };

      final shift = ShiftModel.fromJson(json);
      expect(shift.preShiftBufferMinutes, 45);
      expect(shift.postShiftBufferMinutes, 180);
      expect(shift.preShiftBuffer, const Duration(minutes: 45));
      expect(shift.postShiftBuffer, const Duration(minutes: 180));
      expect(shift.allowPreShiftCheckIn, isTrue);
      expect(shift.allowPostShiftCheckOut, isFalse);

      final serialized = shift.toJson();
      expect(serialized['PreShiftBufferMinutes'], 45);
      expect(serialized['PostShiftBufferMinutes'], 180);
      expect(serialized['AllowPreShiftCheckIn'], isTrue);
      expect(serialized['AllowPostShiftCheckOut'], isFalse);
    });
  });

  group('OfflineCacheService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Employee list caching with face embeddings and retrieval', () async {
      final employees = [
        EmployeeModel(
          employeeId: 1,
          employeeNo: 'EMP101',
          mobileCode: 'EMP101',
          name: 'Alice',
          faceEmbedding: [0.12, -0.45, 0.88, 0.01],
        ),
        EmployeeModel(
          employeeId: 2,
          employeeNo: 'EMP102',
          mobileCode: 'EMP102',
          name: 'Bob',
          faceEmbedding: [0.33, 0.44, -0.55, 0.66],
        ),
      ];

      await OfflineCacheService.cacheEmployeeList(employees);
      final retrieved = await OfflineCacheService.getEmployeeList();

      expect(retrieved.length, 2);
      expect(retrieved[0].name, 'Alice');
      expect(retrieved[0].mobileCode, 'EMP101');
      expect(retrieved[0].faceEmbedding, [0.12, -0.45, 0.88, 0.01]);
      expect(retrieved[1].name, 'Bob');
      expect(retrieved[1].mobileCode, 'EMP102');
      expect(retrieved[1].faceEmbedding, [0.33, 0.44, -0.55, 0.66]);
    });

    test('Shift caching and retrieval', () async {
      const shift = ShiftModel(
        employeeNo: 'EMP201',
        shiftName: 'Morning Shift',
        inTime: '08:00:00',
        outTime: '16:00:00',
      );

      await OfflineCacheService.cacheShift('EMP201', shift);
      final retrieved = await OfflineCacheService.getShift('EMP201');

      expect(retrieved, isNotNull);
      expect(retrieved!.shiftName, 'Morning Shift');
      expect(retrieved.inTime, '08:00:00');
      expect(retrieved.outTime, '16:00:00');
    });

    test('Attendance history caching and retrieval', () async {
      final history = [
        AttendanceHistoryModel(
          employeeNo: 'EMP301',
          transactionId: 12345,
          checkTime: DateTime(2026, 10, 6, 9, 5),
          checkOutTime: null,
          punchDate: DateTime(2026, 10, 6),
        ),
      ];

      await OfflineCacheService.cacheHistory('EMP301', history);
      final retrieved = await OfflineCacheService.getHistory('EMP301');

      expect(retrieved.length, 1);
      expect(retrieved[0].employeeNo, 'EMP301');
      expect(retrieved[0].checkTime, DateTime(2026, 10, 6, 9, 5));
      expect(retrieved[0].checkOutTime, isNull);
    });

    test('CheckStatus derived caching and retrieval', () async {
      final status = CheckStatusModel(
        status: 'checkin',
        latestPunchTime: DateTime(2026, 10, 6, 9, 10).toIso8601String(),
        punchDate: DateTime(2026, 10, 6).toIso8601String(),
        checkedInForShift: true,
      );

      await OfflineCacheService.cacheCheckStatus('EMP401', status);
      final retrieved = await OfflineCacheService.getCheckStatus('EMP401');

      expect(retrieved, isNotNull);
      expect(retrieved!.status, 'checkin');
      expect(retrieved.checkedInForShift, isTrue);
    });
  });

  group('OfflineServices Resolution Logic Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default status when no data exists is checkout', () async {
      final result = await OfflineServices.determineCheckStatus('EMP501');
      expect(result.status, 'checkout');
    });

    test('Status resolved from cached attendance history (checked in)', () async {
      final today = DateTime.now();
      final history = [
        AttendanceHistoryModel(
          employeeNo: 'EMP502',
          transactionId: 999,
          checkTime: today.subtract(const Duration(hours: 2)),
          checkOutTime: null, // Still checked in
          punchDate: DateTime(today.year, today.month, today.day),
        ),
      ];

      await OfflineCacheService.cacheHistory('EMP502', history);
      final result = await OfflineServices.determineCheckStatus('EMP502');

      expect(result.status, 'checkin');
      expect(result.checkedInForShift, isTrue);
    });

    test('Status resolved from cached attendance history (checked out)', () async {
      final today = DateTime.now();
      final history = [
        AttendanceHistoryModel(
          employeeNo: 'EMP503',
          transactionId: 1000,
          checkTime: today.subtract(const Duration(hours: 4)),
          checkOutTime: today.subtract(const Duration(hours: 1)), // Checked out
          punchDate: DateTime(today.year, today.month, today.day),
        ),
      ];

      await OfflineCacheService.cacheHistory('EMP503', history);
      final result = await OfflineServices.determineCheckStatus('EMP503');

      expect(result.status, 'checkout');
    });

    test('updateCachedStatusAfterPunch updates history and derived status correctly', () async {
      final punchTime = DateTime(2026, 10, 6, 9, 15);

      // 1. First punch: Android_IN (check-in)
      await OfflineServices.updateCachedStatusAfterPunch(
        employeeNo: 'EMP504',
        checkType: 'Android_IN',
        punchTime: punchTime,
      );

      // Verify derived check status is now 'checkin'
      final cachedStatus = await OfflineCacheService.getCheckStatus('EMP504');
      expect(cachedStatus, isNotNull);
      expect(cachedStatus!.status, 'checkin');

      // Verify cached history has checkTime set and checkOutTime null
      final historyList = await OfflineCacheService.getHistory('EMP504');
      expect(historyList.length, 1);
      expect(historyList[0].checkTime, punchTime);
      expect(historyList[0].checkOutTime, isNull);

      // 2. Second punch: Android_Out (check-out)
      final outTime = punchTime.add(const Duration(hours: 8));
      await OfflineServices.updateCachedStatusAfterPunch(
        employeeNo: 'EMP504',
        checkType: 'Android_Out',
        punchTime: outTime,
      );

      final cachedStatusAfterOut = await OfflineCacheService.getCheckStatus('EMP504');
      expect(cachedStatusAfterOut!.status, 'checkout');

      final historyAfterOut = await OfflineCacheService.getHistory('EMP504');
      expect(historyAfterOut.length, 1);
      expect(historyAfterOut[0].checkTime, punchTime);
      expect(historyAfterOut[0].checkOutTime, outTime);
    });

    test('ShiftModel.hasValidTiming validates presence of inTime and outTime', () {
      const validShift = ShiftModel(
        employeeNo: 'EMP601',
        inTime: '09:00:00',
        outTime: '18:00:00',
      );
      expect(validShift.hasValidTiming, isTrue);

      const noInTime = ShiftModel(
        employeeNo: 'EMP602',
        inTime: null,
        outTime: '18:00:00',
      );
      expect(noInTime.hasValidTiming, isFalse);

      const emptyInTime = ShiftModel(
        employeeNo: 'EMP603',
        inTime: '   ',
        outTime: '18:00:00',
      );
      expect(emptyInTime.hasValidTiming, isFalse);

      const noOutTime = ShiftModel(
        employeeNo: 'EMP604',
        inTime: '09:00:00',
        outTime: null,
      );
      expect(noOutTime.hasValidTiming, isFalse);

      const emptyOutTime = ShiftModel(
        employeeNo: 'EMP605',
        inTime: '09:00:00',
        outTime: '   ',
      );
      expect(emptyOutTime.hasValidTiming, isFalse);
    });

    test('OfflineServices.isShiftAvailable checks if valid shift is cached', () async {
      // 1. No shift cached -> false
      expect(await OfflineServices.isShiftAvailable('EMP_NO_SHIFT'), isFalse);

      // 2. Shift with invalid timing cached -> false
      await OfflineCacheService.cacheShift('EMP_INVALID_SHIFT', const ShiftModel(
        employeeNo: 'EMP_INVALID_SHIFT',
        inTime: '',
        outTime: null,
      ));
      expect(await OfflineServices.isShiftAvailable('EMP_INVALID_SHIFT'), isFalse);

      // 3. Shift with valid timing cached -> true
      await OfflineCacheService.cacheShift('EMP_VALID_SHIFT', const ShiftModel(
        employeeNo: 'EMP_VALID_SHIFT',
        inTime: '09:00:00',
        outTime: '18:00:00',
      ));
      expect(await OfflineServices.isShiftAvailable('EMP_VALID_SHIFT'), isTrue);
    });

    test('OfflineCacheService.getAllCachedShifts and clearAllShifts work properly', () async {
      await OfflineCacheService.cacheShift('EMP701', const ShiftModel(
        employeeNo: 'EMP701',
        shiftName: 'Morning Shift',
        inTime: '08:00:00',
        outTime: '16:00:00',
      ));
      await OfflineCacheService.cacheShift('EMP702', const ShiftModel(
        employeeNo: 'EMP702',
        shiftName: 'Evening Shift',
        inTime: '16:00:00',
        outTime: '00:00:00',
      ));

      final allShifts = await OfflineCacheService.getAllCachedShifts();
      expect(allShifts.containsKey('EMP701'), isTrue);
      expect(allShifts['EMP701']!.shiftName, 'Morning Shift');
      expect(allShifts.containsKey('EMP702'), isTrue);
      expect(allShifts['EMP702']!.shiftName, 'Evening Shift');

      // Clear all
      await OfflineCacheService.clearAllShifts();
      final afterClear = await OfflineCacheService.getAllCachedShifts();
      expect(afterClear.isEmpty, isTrue);
    });

    test('OfflineCacheService.getAllCachedHistories and clearAllHistories work properly', () async {
      final h1 = [
        AttendanceHistoryModel(
          employeeNo: 'EMP801',
          checkTime: DateTime(2026, 10, 7, 9, 0),
          checkOutTime: null,
          punchDate: DateTime(2026, 10, 7),
        ),
      ];
      final h2 = [
        AttendanceHistoryModel(
          employeeNo: 'EMP802',
          checkTime: DateTime(2026, 10, 7, 8, 30),
          checkOutTime: DateTime(2026, 10, 7, 17, 30),
          punchDate: DateTime(2026, 10, 7),
        ),
      ];

      await OfflineCacheService.cacheHistory('EMP801', h1);
      await OfflineCacheService.cacheHistory('EMP802', h2);

      final allHistories = await OfflineCacheService.getAllCachedHistories();
      expect(allHistories.containsKey('EMP801'), isTrue);
      expect(allHistories['EMP801']!.length, 1);
      expect(allHistories['EMP801']![0].checkOutTime, isNull);
      expect(allHistories.containsKey('EMP802'), isTrue);
      expect(allHistories['EMP802']!.length, 1);
      expect(allHistories['EMP802']![0].checkOutTime, isNotNull);

      // Clear all histories
      await OfflineCacheService.clearAllHistories();
      final afterClear = await OfflineCacheService.getAllCachedHistories();
      expect(afterClear.isEmpty, isTrue);
    });

    test('EmployeeModel.effectiveEmployeeNo prioritizes mobileCode over index or 0', () {
      final empWithMobileCode = EmployeeModel(
        mobileCode: 'LTDEMO111241',
        employeeId: 0,
        employeeNo: null,
      );
      expect(empWithMobileCode.effectiveEmployeeNo, 'LTDEMO111241');

      final empWithZeroEmployeeNo = EmployeeModel(
        mobileCode: 'EMP999',
        employeeId: 1,
        employeeNo: '0',
      );
      expect(empWithZeroEmployeeNo.effectiveEmployeeNo, 'EMP999');

      final empOnlyEmployeeNo = EmployeeModel(
        mobileCode: null,
        employeeId: 2,
        employeeNo: 'EMP102',
      );
      expect(empOnlyEmployeeNo.effectiveEmployeeNo, 'EMP102');

      final empIndexOnly = EmployeeModel(
        mobileCode: null,
        employeeId: 0,
        employeeNo: '0',
      );
      expect(empIndexOnly.effectiveEmployeeNo, '');
    });
  });
}


