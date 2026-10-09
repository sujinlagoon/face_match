import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../data/models/shift_model.dart';
import '../../data/url.dart';
import '../../helpers/colors.dart';
import '../../services/offline/offline_cache_service.dart';
import '../../services/offline/offline_services.dart';
import '../../services/offline/shift/shift_window_calculator.dart';
import '../controller/face_match_controller.dart';
import '../model/profile_face_model.dart';

/// Item representing an employee and their corresponding cached shift info.
class EmployeeShiftItem {
  final String employeeNo;
  final String name;
  final String? designation;
  final String? department;
  final String? userImage;
  ShiftModel? shift;
  bool isSyncing;

  EmployeeShiftItem({
    required this.employeeNo,
    required this.name,
    this.designation,
    this.department,
    this.userImage,
    this.shift,
    this.isSyncing = false,
  });

  bool get hasValidShift => shift != null && shift!.hasValidTiming;

  ShiftWindow get activeWindow {
    return ShiftWindowCalculator.resolveActiveWindow(
      shift: shift,
      at: DateTime.now(),
    );
  }

  bool get isCurrentlyInWindow {
    return activeWindow.contains(DateTime.now());
  }
}

class ShiftDebugView extends StatefulWidget {
  const ShiftDebugView({super.key});

  @override
  State<ShiftDebugView> createState() => _ShiftDebugViewState();
}

class _ShiftDebugViewState extends State<ShiftDebugView> {
  bool _isLoading = true;
  bool _isSyncingAll = false;
  String _syncProgressText = '';
  List<EmployeeShiftItem> _items = [];
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Valid Shift', 'No Shift', 'In Window'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllShiftData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllShiftData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Gather employee list from local cache or active controller
      List<EmployeeModel> cachedEmployees = await OfflineCacheService.getEmployeeList();
      if (cachedEmployees.isEmpty && Get.isRegistered<FaceMatchController>()) {
        final ctrl = Get.find<FaceMatchController>();
        if (ctrl.employeeList.isNotEmpty) {
          cachedEmployees = ctrl.employeeList;
        }
      }

      // 2. Gather all cached shifts from SharedPreferences
      final Map<String, ShiftModel> cachedShifts =
          await OfflineCacheService.getAllCachedShifts();

      // 3. Build a consolidated set of employee numbers
      final Map<String, EmployeeShiftItem> itemMap = {};

      for (final emp in cachedEmployees) {
        final empNo = emp.effectiveEmployeeNo;
        if (empNo.isNotEmpty && empNo != '0' && empNo != '1') {
          itemMap[empNo] = EmployeeShiftItem(
            employeeNo: empNo,
            name: emp.name ?? 'Employee $empNo',
            designation: emp.designation,
            department: emp.department,
            userImage: emp.userImage,
            shift: cachedShifts[empNo] ?? await OfflineCacheService.getShift(empNo),
          );
        }
      }

      // Include any employee numbers that have cached shifts but were not in employee list
      for (final entry in cachedShifts.entries) {
        final empNo = entry.key;
        if (!itemMap.containsKey(empNo) && empNo.isNotEmpty && empNo != '0' && empNo != '1') {
          itemMap[empNo] = EmployeeShiftItem(
            employeeNo: empNo,
            name: 'Employee $empNo',
            shift: entry.value,
          );
        }
      }

      // Sort: Valid shifts first, then by Employee No
      final list = itemMap.values.toList()
        ..sort((a, b) {
          if (a.hasValidShift && !b.hasValidShift) return -1;
          if (!a.hasValidShift && b.hasValidShift) return 1;
          return a.employeeNo.compareTo(b.employeeNo);
        });

      if (mounted) {
        setState(() {
          _items = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[ShiftDebugView] Error loading shift data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Syncs shift for a single employee from server and updates local cache
  Future<void> _syncSingleShift(EmployeeShiftItem item) async {
    setState(() => item.isSyncing = true);

    try {
      final shift = await OfflineServices.fetchAndCacheShift(item.employeeNo);
      if (mounted) {
        setState(() {
          item.shift = shift;
          item.isSyncing = false;
        });
        Get.snackbar(
          'Shift Updated',
          shift != null
              ? 'Shift "${shift.shiftName}" cached for ${item.name} (${item.employeeNo})'
              : 'No shift found on server for ${item.name}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: shift != null ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => item.isSyncing = false);
        Get.snackbar(
          'Sync Failed',
          'Could not fetch shift for ${item.employeeNo}: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: const Color(0xFFEF4444),
          colorText: Colors.white,
        );
      }
    }
  }

  /// Clears cached shift for a single employee
  Future<void> _clearSingleShift(EmployeeShiftItem item) async {
    await OfflineCacheService.clearShift(item.employeeNo);
    if (mounted) {
      setState(() {
        item.shift = null;
      });
      Get.snackbar(
        'Shift Cleared',
        'Cached shift removed for ${item.name} (${item.employeeNo}). Offline check will be rejected.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF64748B),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// Syncs shifts for all displayed employees sequentially
  Future<void> _syncAllShifts() async {
    if (_isSyncingAll || _items.isEmpty) return;

    setState(() {
      _isSyncingAll = true;
      _syncProgressText = '0/${_items.length} synced';
    });

    int count = 0;
    int successCount = 0;

    for (final item in _items) {
      try {
        final shift = await OfflineServices.fetchAndCacheShift(item.employeeNo);
        if (shift != null) {
          successCount++;
          item.shift = shift;
        }
      } catch (_) {}

      count++;
      if (mounted) {
        setState(() {
          _syncProgressText = '$count/${_items.length} synced';
        });
      }
    }

    if (mounted) {
      setState(() {
        _isSyncingAll = false;
        _syncProgressText = '';
      });
      Get.snackbar(
        'Bulk Shift Sync Completed',
        'Updated shifts for $successCount of ${_items.length} employee(s)',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF10B981),
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Fetch employee list from server if empty
  Future<void> _fetchEmployeesFromServer() async {
    setState(() => _isLoading = true);

    try {
      if (Get.isRegistered<FaceMatchController>()) {
        final ctrl = Get.find<FaceMatchController>();
        final success = await ctrl.faceMatchApi(timeKeeperId: 'LTDEMO111241');
        if (success) {
          Get.snackbar(
            'Employees Loaded',
            'Loaded and cached ${ctrl.employeeList.length} employee profile(s)',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: const Color(0xFF10B981),
            colorText: Colors.white,
          );
          await _loadAllShiftData();
          return;
        }
      }

      final uri = Uri.parse('${Url.faceMatch}?EmployeeNo=LTDEMO111241');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

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
            .map((item) => EmployeeModel.fromJson(item as Map<String, dynamic>))
            .toList();

        await OfflineCacheService.cacheEmployeeList(parsedList);

        Get.snackbar(
          'Employees Loaded',
          'Loaded and cached ${parsedList.length} employee profile(s)',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: const Color(0xFF10B981),
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Server Error',
          'Failed to load employees (${response.statusCode})',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: const Color(0xFFEF4444),
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Connection Error',
        'Could not connect to server: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        colorText: Colors.white,
      );
    } finally {
      await _loadAllShiftData();
    }
  }

  List<EmployeeShiftItem> get _filteredItems {
    return _items.where((item) {
      // Search filter
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchNo = item.employeeNo.toLowerCase().contains(query);
        final matchName = item.name.toLowerCase().contains(query);
        final matchShift = item.shift?.shiftName?.toLowerCase().contains(query) ?? false;
        if (!matchNo && !matchName && !matchShift) return false;
      }

      // Tab filter
      switch (_selectedFilter) {
        case 'Valid Shift':
          return item.hasValidShift;
        case 'No Shift':
          return !item.hasValidShift;
        case 'In Window':
          return item.hasValidShift && item.isCurrentlyInWindow;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _items.where((i) => i.hasValidShift).length;
    final missingCount = _items.where((i) => !i.hasValidShift).length;
    final inWindowCount =
        _items.where((i) => i.hasValidShift && i.isCurrentlyInWindow).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Employee Shift Debug',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isSyncingAll)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      _syncProgressText,
                      style: TextStyle(fontSize: 11.sp, color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: Colors.white),
              tooltip: 'Sync All Shifts',
              onPressed: _items.isEmpty ? null : _syncAllShifts,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (value) async {
                if (value == 'clear_all') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear All Shifts?'),
                      content: const Text(
                        'This will delete all locally cached shifts for all employees. You can re-sync anytime.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await OfflineCacheService.clearAllShifts();
                    await _loadAllShiftData();
                  }
                } else if (value == 'reload_employees') {
                  await _fetchEmployeesFromServer();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'reload_employees',
                  child: Row(
                    children: [
                      Icon(Icons.people_alt_rounded, size: 18, color: Color(0xFF4F46E5)),
                      SizedBox(width: 10),
                      Text('Fetch Employees from API'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Clear All Cached Shifts'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllShiftData,
        color: AppColors.primary,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Top Overview Summary Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
                      child: _buildSummaryMetrics(
                        total: _items.length,
                        valid: validCount,
                        missing: missingCount,
                        inWindow: inWindowCount,
                      ),
                    ),
                  ),

                  // Search and Filter Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchBar(),
                          SizedBox(height: 12.h),
                          _buildFilterTabs(
                            total: _items.length,
                            valid: validCount,
                            missing: missingCount,
                            inWindow: inWindowCount,
                          ),
                          SizedBox(height: 12.h),
                        ],
                      ),
                    ),
                  ),

                  // Employee Cards List
                  if (_filteredItems.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 32.h),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _filteredItems[index];
                            return _buildEmployeeShiftCard(item);
                          },
                          childCount: _filteredItems.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSummaryMetrics({
    required int total,
    required int valid,
    required int missing,
    required int inWindow,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
              ),
              SizedBox(width: 8.w),
              Text(
                'Shift Coverage Overview',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  total > 0 ? '${((valid / total) * 100).toInt()}% Ready' : '0% Ready',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              _buildMetricTile('Total Staff', '$total', const Color(0xFF94A3B8)),
              _buildMetricTile('Valid Shifts', '$valid', const Color(0xFF34D399)),
              _buildMetricTile('No Shift', '$missing', const Color(0xFFF87171)),
              _buildMetricTile('In Window Now', '$inWindow', const Color(0xFF38BDF8)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          SizedBox(height: 3.h),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.sp,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(fontSize: 13.sp),
        decoration: InputDecoration(
          hintText: 'Search by employee name or ID...',
          hintStyle: TextStyle(fontSize: 13.sp, color: const Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val);
        },
      ),
    );
  }

  Widget _buildFilterTabs({
    required int total,
    required int valid,
    required int missing,
    required int inWindow,
  }) {
    final filters = [
      {'name': 'All', 'count': total},
      {'name': 'Valid Shift', 'count': valid},
      {'name': 'No Shift', 'count': missing},
      {'name': 'In Window', 'count': inWindow},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['name'];
          return Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: FilterChip(
              selected: isSelected,
              label: Text(
                '${f['name']} (${f['count']})',
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              backgroundColor: Colors.white,
              selectedColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.r),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                ),
              ),
              onSelected: (_) {
                setState(() => _selectedFilter = f['name'] as String);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmployeeShiftCard(EmployeeShiftItem item) {
    final shift = item.shift;
    final hasValidShift = item.hasValidShift;
    final inWindow = hasValidShift && item.isCurrentlyInWindow;
    final window = item.activeWindow;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: hasValidShift
              ? (inWindow ? const Color(0xFF38BDF8) : const Color(0xFFE2E8F0))
              : const Color(0xFFFECACA),
          width: inWindow ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Avatar, Name, Employee ID, Status Chips
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20.r,
                  backgroundColor: hasValidShift
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFFEF4444).withValues(alpha: 0.15),
                  child: Text(
                    item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: hasValidShift
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Shift status badge
                          _buildBadge(
                            label: hasValidShift
                                ? 'Valid Shift'
                                : (shift == null ? 'No Shift' : 'Invalid Timing'),
                            color: hasValidShift
                                ? const Color(0xFF10B981)
                                : (shift == null
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFF59E0B)),
                          ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      Row(
                        children: [
                          Text(
                            'ID: ${item.employeeNo}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          if (item.department != null && item.department!.isNotEmpty) ...[
                            Text(' • ', style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 11.sp)),
                            Expanded(
                              child: Text(
                                item.department!,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 12.h),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            SizedBox(height: 10.h),

            // Shift Details Section
            if (shift != null) ...[
              // Shift name and in/out time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_rounded, size: 14, color: Color(0xFF64748B)),
                      SizedBox(width: 4.w),
                      Text(
                        shift.shiftName ?? 'Unnamed Shift',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      if (shift.shiftCode != null && shift.shiftCode!.isNotEmpty)
                        Text(
                          ' (${shift.shiftCode})',
                          style: TextStyle(fontSize: 11.sp, color: const Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      '${shift.inTime ?? '--:--'} – ${shift.outTime ?? '--:--'}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10.h),

              // Buffers & Policies grid
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildDetailCell(
                          'Pre-Shift Buffer',
                          '${shift.preShiftBufferMinutes ?? 60} min (${shift.allowPreShiftCheckIn ? 'Allowed' : 'Disabled'})',
                          shift.allowPreShiftCheckIn ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                        _buildDetailCell(
                          'Post-Shift Buffer',
                          '${shift.postShiftBufferMinutes ?? 480} min (${shift.allowPostShiftCheckOut ? 'Allowed' : 'Disabled'})',
                          shift.allowPostShiftCheckOut ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _buildDetailCell(
                          'Active Window Start',
                          _formatDateTime(window.start),
                          const Color(0xFF334155),
                        ),
                        _buildDetailCell(
                          'Active Window End',
                          _formatDateTime(window.end),
                          const Color(0xFF334155),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 8.h),

              // Window Status banner
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: inWindow
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  children: [
                    Icon(
                      inWindow ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 15,
                      color: inWindow ? const Color(0xFF059669) : const Color(0xFF64748B),
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        inWindow
                            ? 'Currently inside active shift window (Offline punch eligible)'
                            : 'Currently outside active window (${window.overnight ? "Overnight" : "Standard"})',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: inWindow ? const Color(0xFF047857) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // No shift warning box
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFFEE2E2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No shift cached for this employee',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            'Offline checks will be rejected with an error toast.',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 10.h),

            // Action Buttons Row (Sync from API, Clear Cache)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (shift != null)
                  TextButton.icon(
                    onPressed: () => _clearSingleShift(item),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFF64748B)),
                    label: Text(
                      'Clear Cache',
                      style: TextStyle(fontSize: 11.sp, color: const Color(0xFF64748B)),
                    ),
                  ),
                SizedBox(width: 6.w),
                item.isSyncing
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: SizedBox(
                          width: 14.w,
                          height: 14.w,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _syncSingleShift(item),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF334155)),
                        label: Text(
                          shift != null ? 'Re-sync' : 'Fetch Shift',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.r),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.r),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded, size: 48, color: Color(0xFF64748B)),
            ),
            SizedBox(height: 16.h),
            Text(
              _items.isEmpty ? 'No Employees Found in Local Cache' : 'No Matching Employees',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6.h),
            Text(
              _items.isEmpty
                  ? 'Employees must be fetched from server before shifts can be mapped.'
                  : 'Try adjusting your search query or filter chip.',
              style: TextStyle(
                fontSize: 12.sp,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            if (_items.isEmpty) ...[
              SizedBox(height: 20.h),
              ElevatedButton.icon(
                onPressed: _fetchEmployeesFromServer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                icon: const Icon(Icons.cloud_download_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'Load Employees from Server',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$hour:$minute ($day/$month)';
  }
}
