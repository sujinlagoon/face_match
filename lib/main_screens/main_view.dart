import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../helpers/colors.dart';
import '../helpers/routes.dart';
import '../services/network/network_controller.dart';
import '../services/offline/offline_punch_store.dart';
import 'debug/debug_settings_view.dart';
import 'face_match_camera_screen.dart';
import 'face_register_screen.dart';
import 'unsynced_records_view.dart';

class MainView extends StatelessWidget {
  final String employeeId;

  const MainView({
    super.key,
    this.employeeId = 'LTDEMO111241',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Face Recognition Portal',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          // Unsynced Records Quick Icon with Badge
          if (Get.isRegistered<NetworkController>())
            Obx(() {
              final count = Get.find<NetworkController>().pendingCount.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cloud_sync_rounded, color: Colors.white),
                    tooltip: 'Unsynced Records',
                    onPressed: () async {
                      await Get.to(
                        () => const UnsyncedRecordsView(),
                        transition: Transition.rightToLeft,
                      );
                      Get.find<NetworkController>().refreshPendingOfflineCount();
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8.h,
                      right: 8.w,
                      child: Container(
                        padding: EdgeInsets.all(3.r),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF9100),
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16.w,
                          minHeight: 16.w,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            })
          else
            FutureBuilder<int>(
              future: OfflinePunchStore.getUnsyncedCount(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.cloud_sync_rounded, color: Colors.white),
                      tooltip: 'Unsynced Records',
                      onPressed: () {
                        Get.to(
                          () => const UnsyncedRecordsView(),
                          transition: Transition.rightToLeft,
                        );
                      },
                    ),
                    if (count > 0)
                      Positioned(
                        top: 8.h,
                        right: 8.w,
                        child: Container(
                          padding: EdgeInsets.all(3.r),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF9100),
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 16.w,
                            minHeight: 16.w,
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.sp,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          // Menu with navigation options
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'Menu',
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            onSelected: (value) async {
              if (value == 'unsynced') {
                await Get.to(
                  () => const UnsyncedRecordsView(),
                  transition: Transition.rightToLeft,
                );
                if (Get.isRegistered<NetworkController>()) {
                  Get.find<NetworkController>().refreshPendingOfflineCount();
                }
              } else if (value == 'logout') {
                Get.offAllNamed(Routes.login);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'unsynced',
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      color: const Color(0xFFFF9100),
                      size: 20.sp,
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      'Unsynced Records',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2B2D42),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 20.sp,
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 0.h),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Welcome Banner Card
              // Container(
              //   padding: EdgeInsets.all(20.r),
              //   decoration: BoxDecoration(
              //     gradient: const LinearGradient(
              //       colors: [
              //         AppColors.primary,
              //         AppColors.primaryLight,
              //       ],
              //       begin: Alignment.topLeft,
              //       end: Alignment.bottomRight,
              //     ),
              //     borderRadius: BorderRadius.circular(20.r),
              //     boxShadow: [
              //       BoxShadow(
              //         color: AppColors.primary.withOpacity(0.25),
              //         blurRadius: 15,
              //         offset: const Offset(0, 6),
              //       ),
              //     ],
              //   ),
              //   child: Row(
              //     children: [
              //       Container(
              //         width: 56.w,
              //         height: 56.w,
              //         decoration: BoxDecoration(
              //           color: Colors.white.withOpacity(0.2),
              //           shape: BoxShape.circle,
              //           border: Border.all(
              //             color: Colors.white.withOpacity(0.4),
              //             width: 1.5,
              //           ),
              //         ),
              //         child: Icon(
              //           Icons.face_retouching_natural_rounded,
              //           size: 32.sp,
              //           color: Colors.white,
              //         ),
              //       ),
              //       SizedBox(width: 16.w),
              //       Expanded(
              //         child: Column(
              //           crossAxisAlignment: CrossAxisAlignment.start,
              //           children: [
              //             Text(
              //               'Welcome Back!',
              //               style: TextStyle(
              //                 fontSize: 18.sp,
              //                 fontWeight: FontWeight.bold,
              //                 color: Colors.white,
              //               ),
              //             ),
              //             SizedBox(height: 4.h),
              //             Text(
              //               'Employee ID: $employeeId',
              //               style: TextStyle(
              //                 fontSize: 13.sp,
              //                 color: Colors.white.withOpacity(0.9),
              //               ),
              //             ),
              //           ],
              //         ),
              //       ),
              //     ],
              //   ),
              // ),

              SizedBox(height: 24.h),

              // Timetick-style Offline Pending Chip
              if (Get.isRegistered<NetworkController>())
                Obx(() {
                  final netCtrl = Get.find<NetworkController>();
                  final count = netCtrl.pendingCount.value;
                  if (count >= 1) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: 20.h),
                      child: _OfflinePendingChip(
                        count: count,
                        onTap: () async {
                          await Get.to(
                            () => const UnsyncedRecordsView(),
                            transition: Transition.rightToLeft,
                          );
                          netCtrl.refreshPendingOfflineCount();
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                })
              else
                FutureBuilder<int>(
                  future: OfflinePunchStore.getUnsyncedCount(),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count >= 1) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 20.h),
                        child: _OfflinePendingChip(
                          count: count,
                          onTap: () => Get.to(
                            () => const UnsyncedRecordsView(),
                            transition: Transition.rightToLeft,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

              // Section Header
              Text(
                'Biometric Actions',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2D42),
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'Select an action to proceed with facial recognition or enrollment.',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF6C757D),
                ),
              ),

              SizedBox(height: 20.h),

              // Face Match Card / Button
              _buildActionCard(
                context: context,
                title: 'Face Match',
                subtitle:
                    'Perform real-time biometric verification and attendance match.',
                icon: Icons.center_focus_strong_rounded,
                badgeText: 'Verify',
                badgeColor: AppColors.primary,
                onTap: () async {
                  await Get.to(
                    () => FaceMatchCameraScreen(
                      userKey: employeeId,
                      timeKeeperId: employeeId,
                    ),
                    transition: Transition.rightToLeft,
                  );
                  if (Get.isRegistered<NetworkController>()) {
                    Get.find<NetworkController>().refreshPendingOfflineCount();
                  }
                },
              ),

              SizedBox(height: 20.h),

              // Register Face Card / Button
              _buildActionCard(
                context: context,
                title: 'Face Register',
                subtitle:
                    'Scan and register new facial features for biometric enrollment.',
                icon: Icons.person_add_alt_1_rounded,
                badgeText: 'Register',
                badgeColor: AppColors.primaryLight,
                onTap: () async {
                  await Get.to(
                    () => FaceRegisterScreen(
                      employeeId: employeeId,
                    ),
                    transition: Transition.rightToLeft,
                  );
                  if (Get.isRegistered<NetworkController>()) {
                    Get.find<NetworkController>().refreshPendingOfflineCount();
                  }
                },
              ),

              SizedBox(height: 20.h),

              // Unsynced Records Card / Button
              _buildActionCard(
                context: context,
                title: 'Unsynced Records',
                subtitle:
                    'Review offline attendance punches and synchronize with server.',
                icon: Icons.cloud_sync_rounded,
                badgeText: 'Offline',
                badgeColor: const Color(0xFFFF9100),
                onTap: () async {
                  await Get.to(
                    () => const UnsyncedRecordsView(),
                    transition: Transition.rightToLeft,
                  );
                  if (Get.isRegistered<NetworkController>()) {
                    Get.find<NetworkController>().refreshPendingOfflineCount();
                  }
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: kDebugMode
          ? FloatingActionButton.extended(
              heroTag: 'debug_settings_fab',
              backgroundColor: const Color(0xFF1E293B),
              elevation: 4,
              icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
              label: Text(
                'Debug Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              onPressed: () {
                Get.to(
                  () => const DebugSettingsView(),
                  transition: Transition.rightToLeft,
                );
              },
            )
          : null,
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: const Color(0xFFE9ECEF),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          splashColor: badgeColor.withValues(alpha: 0.1),
          highlightColor: badgeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Row(
              children: [
                // Icon Box
                Container(
                  width: 52.w,
                  height: 52.w,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    size: 28.sp,
                    color: badgeColor,
                  ),
                ),
                SizedBox(width: 14.w),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2B2D42),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: const Color(0xFF6C757D),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 8.w),

                // Arrow Indicator
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16.sp,
                  color: const Color(0xFFADB5BD),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Offline pending records card styled after Timetick's _OfflinePendingChip
class _OfflinePendingChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _OfflinePendingChip({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: const Color(0xFFFFCC80), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9100).withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(7.r),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE0B2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 20.sp,
                  color: const Color(0xFFE65100),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count offline punch${count == 1 ? '' : 'es'} pending',
                      style: TextStyle(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFBF360C),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Tap to view and synchronize with server',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: const Color(0xFFE65100).withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFFE65100),
                size: 24.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
