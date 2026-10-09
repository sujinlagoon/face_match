import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../services/network/network_controller.dart';

/// Global wrapper that places the Timetick offline & sync banner at the bottom of the screen.
class BottomOfflineBannerWrapper extends StatelessWidget {
  final Widget? child;

  const BottomOfflineBannerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Expanded(
            child: child ?? const SizedBox.shrink(),
          ),
          const BottomOfflineBanner(),
        ],
      ),
    );
  }
}

/// Bottom-docked offline, syncing, and connection restored banner inspired by Timetick.
class BottomOfflineBanner extends StatelessWidget {
  const BottomOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NetworkController>()) {
      return const SizedBox.shrink();
    }

    final networkController = Get.find<NetworkController>();

    return Obx(() {
      final state = networkController.bannerState.value;
      final bool isVisible = state != BannerState.none;
      final syncCompleted = networkController.syncedCount.value;
      final syncTotal = networkController.syncTotal.value;
      final bool allRecordsSynced = networkController.allRecordsSynced.value;
      final bool syncPartialFailure = networkController.syncPartialFailure.value;
      final bool isSyncing = state == BannerState.syncing;

      final double? syncProgress =
          syncTotal > 0 ? (syncCompleted / syncTotal).clamp(0.0, 1.0) : null;

      Gradient bannerGradient = const LinearGradient(
        colors: [Color(0xFFE53935), Color(0xFFC62828)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
      String bannerText = "Offline Mode";
      String? bannerSubtitle;
      IconData bannerIcon = Icons.wifi_off_rounded;

      if (state == BannerState.offline) {
        bannerGradient = const LinearGradient(
          colors: [Color(0xFFE53935), Color(0xFFC62828)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );
        bannerText = "Offline Mode";
        bannerSubtitle = "Check In/Out is still active & saving locally";
        bannerIcon = Icons.wifi_off_rounded;
      } else if (state == BannerState.syncing) {
        bannerGradient = const LinearGradient(
          colors: [Color(0xFFFFA000), Color(0xFFEF6C00)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );
        bannerText = allRecordsSynced
            ? 'All records synced'
            : (syncTotal > 0
                ? 'Syncing ${syncCompleted.clamp(0, syncTotal)}/$syncTotal'
                : 'Syncing Records');
        bannerSubtitle = allRecordsSynced
            ? 'No pending offline attendance logs'
            : 'Uploading offline attendance logs...';
        bannerIcon = Icons.sync_rounded;
      } else if (state == BannerState.backOnline) {
        if (syncPartialFailure) {
          bannerGradient = const LinearGradient(
            colors: [Color(0xFFFFA000), Color(0xFFEF6C00)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );
          bannerIcon = Icons.sync_problem_rounded;
        } else {
          bannerGradient = const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );
          bannerIcon = Icons.wifi_rounded;
        }
        bannerText = "Connection Restored";
        bannerSubtitle = networkController.lastSyncBannerSubtitle;
      }

      final double bannerContentHeight = isSyncing ? 58.h : 48.h;
      final bottomInset = MediaQuery.of(context).padding.bottom;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.fastOutSlowIn,
        height: isVisible ? (bannerContentHeight + bottomInset) : 0,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: bannerGradient,
          boxShadow: isVisible
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ]
              : null,
        ),
        child: isVisible
            ? SafeArea(
                top: false,
                bottom: true,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Container(
                    height: bannerContentHeight,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          bannerIcon,
                          color: Colors.white,
                          size: 18.sp,
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bannerText,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (bannerSubtitle != null)
                                Text(
                                  bannerSubtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 10.5.sp,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (isSyncing &&
                                  (syncTotal > 0 || allRecordsSynced)) ...[
                                SizedBox(height: 5.h),
                                AnimatedSyncProgressBar(
                                  progress: allRecordsSynced
                                      ? 1.0
                                      : (syncProgress ?? 0.0),
                                ),
                              ] else if (isSyncing) ...[
                                SizedBox(height: 5.h),
                                const AnimatedSyncProgressBar(),
                              ],
                            ],
                          ),
                        ),
                        if (state == BannerState.offline) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 3.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6.w,
                                  height: 6.w,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  "ACTIVE",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    });
  }
}

/// Animated linear progress bar matching Timetick style.
class AnimatedSyncProgressBar extends StatelessWidget {
  final double? progress;

  const AnimatedSyncProgressBar({super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    if (progress == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4.r),
        child: LinearProgressIndicator(
          minHeight: 4.h,
          backgroundColor: Colors.white.withValues(alpha: 0.25),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress!.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4.h,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      },
    );
  }
}
