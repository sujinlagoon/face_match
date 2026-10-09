import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../helpers/colors.dart';
import '../services/network/network_controller.dart';
import '../services/offline/offline_punch_store.dart';
import '../widgets/custom_toast.dart';

class UnsyncedRecordsView extends StatefulWidget {
  const UnsyncedRecordsView({super.key});

  @override
  State<UnsyncedRecordsView> createState() => _UnsyncedRecordsViewState();
}

class _UnsyncedRecordsViewState extends State<UnsyncedRecordsView> {
  List<Map<String, dynamic>> _unsyncedRecords = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncProgressText = '';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await OfflinePunchStore.getUnsynced();
      if (mounted) {
        setState(() {
          _unsyncedRecords = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomToast.showError("Failed to load offline records: $e");
      }
    }
  }

  Future<void> _handleSync() async {
    if (_unsyncedRecords.isEmpty) {
      CustomToast.showSuccess("No offline punches to sync");
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncProgressText = "Syncing punches...";
    });

    try {
      final result = await OfflinePunchStore.syncUnsynced(
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _syncProgressText = "Syncing $done of $total...";
            });
          }
        },
      );

      if (result.syncedCount > 0) {
        CustomToast.showSuccess(
          "Successfully synced ${result.syncedCount} of ${result.total} punch(es)",
        );
      } else {
        CustomToast.showError(
          "Could not sync records. Check network connection and retry.",
        );
      }
    } catch (e) {
      CustomToast.showError("Sync error: $e");
    } finally {
      if (Get.isRegistered<NetworkController>()) {
        Get.find<NetworkController>().refreshPendingOfflineCount();
      }
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgressText = '';
        });
        await _loadRecords();
      }
    }
  }

  Future<void> _confirmDelete(int id, String employeeNo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: const Text(
          "Delete Offline Punch",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to remove the unsynced record for $employeeNo? This punch will not be synced to the server.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await OfflinePunchStore.deletePunch(id);
      CustomToast.showSuccess("Offline punch removed");
      if (Get.isRegistered<NetworkController>()) {
        Get.find<NetworkController>().refreshPendingOfflineCount();
      }
      await _loadRecords();
    }
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final year = dt.year;
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      return '$year-$month-$day • $hour:$minute:$second $period';
    } catch (_) {
      return raw;
    }
  }

  bool _isCheckIn(String? checkType) {
    final s = (checkType ?? '').toUpperCase();
    return s.contains('IN') && !s.contains('OUT');
  }

  @override
  Widget build(BuildContext context) {
    final hasRecords = _unsyncedRecords.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Unsynced Records',
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
          IconButton(
            icon: _isSyncing
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync_rounded, color: Colors.white),
            tooltip: 'Sync Now',
            onPressed: (_isLoading || _isSyncing) ? null : _handleSync,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
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
                  // Top Summary & Action Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                      child: _buildSummaryCard(hasRecords),
                    ),
                  ),

                  // Records Section Title
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Pending Offline Queue",
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2B2D42),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: hasRecords
                                  ? const Color(0xFFFF9100).withOpacity(0.15)
                                  : const Color(0xFF00E676).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: Text(
                              hasRecords
                                  ? "${_unsyncedRecords.length} Pending"
                                  : "Up to date",
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.bold,
                                color: hasRecords
                                    ? const Color(0xFFE65100)
                                    : const Color(0xFF00796B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // List of Records or Empty State
                  if (!hasRecords)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final row = _unsyncedRecords[index];
                            return _buildRecordCard(row);
                          },
                          childCount: _unsyncedRecords.length,
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(child: SizedBox(height: 30.h)),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard(bool hasRecords) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: hasRecords
                      ? const Color(0xFFFF9100).withOpacity(0.12)
                      : const Color(0xFF00E676).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasRecords ? Icons.cloud_queue_rounded : Icons.cloud_done_rounded,
                  color: hasRecords ? const Color(0xFFFF9100) : const Color(0xFF00E676),
                  size: 26.sp,
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasRecords
                          ? "${_unsyncedRecords.length} Unsynced Punch${_unsyncedRecords.length > 1 ? 'es' : ''}"
                          : "All Punches Synced",
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2B2D42),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      hasRecords
                          ? "These records were saved offline and will automatically upload when online."
                          : "Local offline database is clean and completely synchronized.",
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: const Color(0xFF6C757D),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (hasRecords) ...[
            SizedBox(height: 14.h),
            const Divider(color: Color(0xFFF1F3F5), height: 1),
            SizedBox(height: 12.h),

            // Sync Action Button
            SizedBox(
              width: double.infinity,
              height: 44.h,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _handleSync,
                icon: _isSyncing
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                label: Text(
                  _isSyncing ? _syncProgressText : "Sync All Records Now",
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 44.sp,
                color: const Color(0xFF00E676),
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              "No Unsynced Records",
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2B2D42),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              "All attendance punches are up to date on the server. Any new offline punches will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: const Color(0xFF6C757D),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> row) {
    final id = row['id'] as int;
    final empNo = row['employee_no'] as String? ?? 'N/A';
    final checkType = row['check_type'] as String? ?? 'N/A';
    final dateTime = row['date_time'] as String? ?? '';
    final location = row['location'] as String? ?? '';
    final lat = row['latitude'] as String? ?? '';
    final lon = row['longitude'] as String? ?? '';
    final device = row['device_id'] as String? ?? '';

    final isCheckIn = _isCheckIn(checkType);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isCheckIn
              ? const Color(0xFF00E676).withOpacity(0.35)
              : const Color(0xFFFF9100).withOpacity(0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Employee ID & Action Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.r),
                    decoration: BoxDecoration(
                      color: isCheckIn
                          ? const Color(0xFF00E676).withOpacity(0.12)
                          : const Color(0xFFFF9100).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                      color: isCheckIn ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                      size: 16.sp,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empNo,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2B2D42),
                        ),
                      ),
                      Text(
                        "Punch ID #$id",
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: const Color(0xFFADB5BD),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Action Badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: isCheckIn
                      ? const Color(0xFF00E676).withOpacity(0.15)
                      : const Color(0xFFFF9100).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: isCheckIn ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isCheckIn ? "CHECK IN" : "CHECK OUT",
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: isCheckIn ? const Color(0xFF00796B) : const Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 10.h),
          const Divider(color: Color(0xFFF1F3F5), height: 1),
          SizedBox(height: 10.h),

          // Details: Timestamp
          _buildDetailRow(
            icon: Icons.access_time_rounded,
            label: "Time",
            value: _formatDateTime(dateTime),
          ),

          // Location
          if (location.isNotEmpty || (lat.isNotEmpty && lon.isNotEmpty)) ...[
            SizedBox(height: 6.h),
            _buildDetailRow(
              icon: Icons.location_on_outlined,
              label: "Location",
              value: location.isNotEmpty ? location : "$lat, $lon",
            ),
          ],

          // Device ID
          if (device.isNotEmpty) ...[
            SizedBox(height: 6.h),
            _buildDetailRow(
              icon: Icons.devices_rounded,
              label: "Device",
              value: device,
            ),
          ],

          SizedBox(height: 10.h),

          // Footer: Pending chip + Delete button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6.w,
                      height: 6.w,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF9100),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      "Pending Sync",
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF495057),
                      ),
                    ),
                  ],
                ),
              ),

              InkWell(
                onTap: () => _confirmDelete(id, empNo),
                borderRadius: BorderRadius.circular(6.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 14.sp, color: Colors.redAccent),
                      SizedBox(width: 4.w),
                      Text(
                        "Delete",
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14.sp, color: const Color(0xFFADB5BD)),
        SizedBox(width: 6.w),
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6C757D),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF2B2D42),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
