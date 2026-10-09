import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../data/models/attendance_history_model.dart';
import '../../data/models/shift_model.dart';
import '../../helpers/colors.dart';
import '../../services/offline/offline_cache_service.dart';
import '../../services/offline/shift/shift_window_calculator.dart';
import '../controller/face_match_controller.dart';
import '../model/profile_face_model.dart';

/// Item representing an employee and their corresponding cached attendance history.
class EmployeeHistoryItem {
  final String employeeNo;
  final String name;
  final String? designation;
  final String? department;
  final String? userImage;
  ShiftModel? shift;
  List<AttendanceHistoryModel> history;
  bool isExpanded;

  EmployeeHistoryItem({
    required this.employeeNo,
    required this.name,
    this.designation,
    this.department,
    this.userImage,
    this.shift,
    this.history = const [],
    this.isExpanded = false,
  });

  bool get hasHistory => history.isNotEmpty;

  /// Most recent attendance record (sorted by checkTime descending)
  AttendanceHistoryModel? get latestRecord {
    if (history.isEmpty) return null;
    final sorted = List<AttendanceHistoryModel>.from(history)
      ..sort((a, b) {
        final aTime = a.checkTime ?? a.punchDate ?? DateTime(1970);
        final bTime = b.checkTime ?? b.punchDate ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
    return sorted.first;
  }

  bool get isCurrentlyCheckedIn {
    final rec = latestRecord;
    return rec != null && rec.checkTime != null && rec.checkOutTime == null;
  }

  bool get isCurrentlyCheckedOut {
    final rec = latestRecord;
    return rec != null && rec.checkOutTime != null;
  }

  ShiftWindow get activeWindow {
    return ShiftWindowCalculator.resolveActiveWindow(
      shift: shift,
      at: DateTime.now(),
    );
  }
}

class AttendanceHistoryDebugView extends StatefulWidget {
  const AttendanceHistoryDebugView({super.key});

  @override
  State<AttendanceHistoryDebugView> createState() =>
      _AttendanceHistoryDebugViewState();
}

class _AttendanceHistoryDebugViewState
    extends State<AttendanceHistoryDebugView> {
  bool _isLoading = true;
  List<EmployeeHistoryItem> _items = [];
  String _searchQuery = '';
  String _selectedFilter =
      'All'; // 'All', 'With History', 'Checked In', 'Checked Out', 'No History'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllHistoryData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllHistoryData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Gather employee list from local cache or active controller
      List<EmployeeModel> cachedEmployees =
          await OfflineCacheService.getEmployeeList();
      if (cachedEmployees.isEmpty && Get.isRegistered<FaceMatchController>()) {
        final ctrl = Get.find<FaceMatchController>();
        if (ctrl.employeeList.isNotEmpty) {
          cachedEmployees = ctrl.employeeList;
        }
      }

      // 2. Gather all cached attendance histories from SharedPreferences
      final Map<String, List<AttendanceHistoryModel>> cachedHistories =
          await OfflineCacheService.getAllCachedHistories();

      // 3. Gather all cached shifts (for window context)
      final Map<String, ShiftModel> cachedShifts =
          await OfflineCacheService.getAllCachedShifts();

      // 4. Build a consolidated set of employee numbers
      final Map<String, EmployeeHistoryItem> itemMap = {};

      for (final emp in cachedEmployees) {
        final empNo = emp.effectiveEmployeeNo;
        if (empNo.isNotEmpty && empNo != '0' && empNo != '1') {
          itemMap[empNo] = EmployeeHistoryItem(
            employeeNo: empNo,
            name: emp.name ?? 'Employee $empNo',
            designation: emp.designation,
            department: emp.department,
            userImage: emp.userImage,
            shift: cachedShifts[empNo] ??
                await OfflineCacheService.getShift(empNo),
            history: cachedHistories[empNo] ??
                await OfflineCacheService.getHistory(empNo),
          );
        }
      }

      // Include any employee numbers that have cached histories but were not in employee list
      for (final entry in cachedHistories.entries) {
        final empNo = entry.key;
        if (!itemMap.containsKey(empNo) && empNo.isNotEmpty && empNo != '0' && empNo != '1') {
          itemMap[empNo] = EmployeeHistoryItem(
            employeeNo: empNo,
            name: 'Employee $empNo',
            shift: cachedShifts[empNo],
            history: entry.value,
          );
        }
      }

      // Sort: Checked in first, then with history, then by Employee No
      final list = itemMap.values.toList()
        ..sort((a, b) {
          if (a.isCurrentlyCheckedIn && !b.isCurrentlyCheckedIn) return -1;
          if (!a.isCurrentlyCheckedIn && b.isCurrentlyCheckedIn) return 1;
          if (a.hasHistory && !b.hasHistory) return -1;
          if (!a.hasHistory && b.hasHistory) return 1;
          return a.employeeNo.compareTo(b.employeeNo);
        });

      if (mounted) {
        setState(() {
          _items = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AttendanceHistoryDebugView] Error loading history data: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Clears cached attendance history for a single employee
  Future<void> _clearSingleHistory(EmployeeHistoryItem item) async {
    await OfflineCacheService.clearHistory(item.employeeNo);
    if (mounted) {
      setState(() {
        item.history = [];
      });
      Get.snackbar(
        'History Cleared',
        'Cached attendance history removed for ${item.name} (${item.employeeNo}).',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF64748B),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  List<EmployeeHistoryItem> get _filteredItems {
    return _items.where((item) {
      // Search filter
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchNo = item.employeeNo.toLowerCase().contains(query);
        final matchName = item.name.toLowerCase().contains(query);
        if (!matchNo && !matchName) return false;
      }

      // Tab filter
      switch (_selectedFilter) {
        case 'With History':
          return item.hasHistory;
        case 'Checked In':
          return item.isCurrentlyCheckedIn;
        case 'Checked Out':
          return item.isCurrentlyCheckedOut;
        case 'No History':
          return !item.hasHistory;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final withHistoryCount = _items.where((i) => i.hasHistory).length;
    final checkedInCount = _items.where((i) => i.isCurrentlyCheckedIn).length;
    final checkedOutCount = _items.where((i) => i.isCurrentlyCheckedOut).length;
    final noHistoryCount = _items.where((i) => !i.hasHistory).length;
    final totalRecords =
        _items.fold<int>(0, (sum, item) => sum + item.history.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Attendance History Debug',
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Reload Local Cache',
            onPressed: _loadAllHistoryData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onSelected: (value) async {
              if (value == 'clear_all') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All Attendance History?'),
                    content: const Text(
                      'This will delete all locally cached attendance histories for all employees.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Clear All',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await OfflineCacheService.clearAllHistories();
                  await _loadAllHistoryData();
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded,
                        size: 18, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Clear All Cached Histories'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllHistoryData,
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
                        withHistory: withHistoryCount,
                        checkedIn: checkedInCount,
                        totalRecords: totalRecords,
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
                            withHistory: withHistoryCount,
                            checkedIn: checkedInCount,
                            checkedOut: checkedOutCount,
                            noHistory: noHistoryCount,
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
                            return _buildEmployeeHistoryCard(item);
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
    required int withHistory,
    required int checkedIn,
    required int totalRecords,
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
                child: const Icon(Icons.history_rounded,
                    color: Colors.white, size: 18),
              ),
              SizedBox(width: 8.w),
              Text(
                'Attendance History Overview',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '$totalRecords Records',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              _buildMetricTile(
                  'Total Staff', '$total', const Color(0xFF94A3B8)),
              _buildMetricTile('With History', '$withHistory',
                  const Color(0xFF38BDF8)),
              _buildMetricTile(
                  'Checked In', '$checkedIn', const Color(0xFF34D399)),
              _buildMetricTile(
                  'Total Punches', '$totalRecords', const Color(0xFFA78BFA)),
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
          hintStyle:
              TextStyle(fontSize: 13.sp, color: const Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFF64748B), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Color(0xFF64748B)),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val);
        },
      ),
    );
  }

  Widget _buildFilterTabs({
    required int total,
    required int withHistory,
    required int checkedIn,
    required int checkedOut,
    required int noHistory,
  }) {
    final filters = [
      {'name': 'All', 'count': total},
      {'name': 'With History', 'count': withHistory},
      {'name': 'Checked In', 'count': checkedIn},
      {'name': 'Checked Out', 'count': checkedOut},
      {'name': 'No History', 'count': noHistory},
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
                  color: isSelected
                      ? AppColors.primary
                      : const Color(0xFFE2E8F0),
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

  Widget _buildEmployeeHistoryCard(EmployeeHistoryItem item) {
    final hasHistory = item.hasHistory;
    final isCheckedIn = item.isCurrentlyCheckedIn;
    final isCheckedOut = item.isCurrentlyCheckedOut;
    final latest = item.latestRecord;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isCheckedIn
              ? const Color(0xFF34D399)
              : (hasHistory
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFCBD5E1)),
          width: isCheckedIn ? 1.5 : 1.0,
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
            // Header Row: Avatar, Name, ID, Badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20.r,
                  backgroundColor: isCheckedIn
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : (hasHistory
                          ? const Color(0xFF0EA5E9).withValues(alpha: 0.15)
                          : const Color(0xFF64748B).withValues(alpha: 0.15)),
                  child: Text(
                    item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: isCheckedIn
                          ? const Color(0xFF047857)
                          : (hasHistory
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF475569)),
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
                          // Status badge
                          _buildBadge(
                            label: isCheckedIn
                                ? '● Checked In'
                                : (isCheckedOut
                                    ? '✓ Checked Out'
                                    : 'No History'),
                            color: isCheckedIn
                                ? const Color(0xFF10B981)
                                : (isCheckedOut
                                    ? const Color(0xFF0EA5E9)
                                    : const Color(0xFF64748B)),
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
                          if (item.department != null &&
                              item.department!.isNotEmpty) ...[
                            Text(' • ',
                                style: TextStyle(
                                    color: const Color(0xFF94A3B8),
                                    fontSize: 11.sp)),
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
                          const Spacer(),
                          Text(
                            '${item.history.length} record(s)',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF64748B),
                            ),
                          ),
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

            // Latest Attendance Record Box
            if (latest != null) ...[
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Latest Attendance Session',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        if (latest.punchDate != null)
                          Text(
                            _formatDateOnly(latest.punchDate!),
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _buildDetailCell(
                          'Check-In (checkTime)',
                          latest.checkTime != null
                              ? _formatTime(latest.checkTime!)
                              : '--:--',
                          latest.checkTime != null
                              ? const Color(0xFF059669)
                              : const Color(0xFF94A3B8),
                        ),
                        _buildDetailCell(
                          'Check-Out (checkOutTime)',
                          latest.checkOutTime != null
                              ? _formatTime(latest.checkOutTime!)
                              : (latest.checkTime != null
                                  ? 'Active Session'
                                  : '--:--'),
                          latest.checkOutTime != null
                              ? const Color(0xFF0284C7)
                              : (latest.checkTime != null
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 8.h),

              // Active Window & Offline Status indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: isCheckedIn
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCheckedIn
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                      size: 15,
                      color: isCheckedIn
                          ? const Color(0xFF059669)
                          : const Color(0xFF0284C7),
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        isCheckedIn
                          ? 'Next offline punch will resolve to CHECK-OUT'
                          : 'Next offline punch will resolve to CHECK-IN',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: isCheckedIn
                              ? const Color(0xFF047857)
                              : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // No history cached box
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: Color(0xFF64748B)),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No attendance history cached locally',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            'Offline status will fall back to derived status or default checkout.',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Expandable List of All Records
            if (item.history.length > 1) ...[
              SizedBox(height: 6.h),
              InkWell(
                onTap: () {
                  setState(() => item.isExpanded = !item.isExpanded);
                },
                borderRadius: BorderRadius.circular(6.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.isExpanded
                            ? 'Hide History Records'
                            : 'View All ${item.history.length} Records',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                      Icon(
                        item.isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: const Color(0xFF4F46E5),
                      ),
                    ],
                  ),
                ),
              ),
              if (item.isExpanded) ...[
                SizedBox(height: 6.h),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: item.history.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (ctx, i) {
                      final rec = item.history[i];
                      return Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 8.h),
                        child: Row(
                          children: [
                            Text(
                              '#${i + 1}',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'IN: ${rec.checkTime != null ? _formatDateTime(rec.checkTime!) : '--'}',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'OUT: ${rec.checkOutTime != null ? _formatDateTime(rec.checkOutTime!) : '--'}',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (rec.transactionId != null) ...[
                                    SizedBox(height: 2.h),
                                    Text(
                                      'Txn ID: ${rec.transactionId}',
                                      style: TextStyle(
                                        fontSize: 9.sp,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],

            SizedBox(height: 10.h),

            // Action Buttons Row (Clear Local Cache only)
            if (hasHistory) ...[
              SizedBox(height: 10.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _clearSingleHistory(item),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 14, color: Color(0xFFEF4444)),
                    label: Text(
                      'Clear History',
                      style: TextStyle(
                          fontSize: 11.sp, color: const Color(0xFFEF4444)),
                    ),
                  ),
                ],
              ),
            ],
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
              child: const Icon(Icons.manage_history_rounded,
                  size: 48, color: Color(0xFF64748B)),
            ),
            SizedBox(height: 16.h),
            Text(
              _items.isEmpty
                  ? 'No Employees Found in Local Cache'
                  : 'No Matching Employees',
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
                  ? 'No cached attendance records found in local storage. Punches performed in offline mode will appear here.'
                  : 'Try adjusting your search query or filter chip.',
              style: TextStyle(
                fontSize: 12.sp,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$hour:$minute ($day/$month)';
  }

  String _formatDateOnly(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
