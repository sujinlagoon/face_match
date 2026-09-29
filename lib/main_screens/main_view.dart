import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../helpers/colors.dart';
import '../helpers/routes.dart';
import 'face_match_camera_screen.dart';
import 'face_register_screen.dart';

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
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () {
              Get.offAllNamed(Routes.login);
            },
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

              SizedBox(height: 32.h),

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
                onTap: () {
                  Get.to(
                    () => FaceMatchCameraScreen(
                      userKey: employeeId,
                      timeKeeperId: employeeId,
                    ),
                    transition: Transition.rightToLeft,
                  );
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
                onTap: () {
                  Get.to(
                    () => FaceRegisterScreen(
                      employeeId: employeeId,
                    ),
                    transition: Transition.rightToLeft,
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
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
          splashColor: badgeColor.withOpacity(0.1),
          highlightColor: badgeColor.withOpacity(0.05),
          child: Padding(
            padding: EdgeInsets.all(18.r),
            child: Row(
              children: [
                // Icon Box
                Container(
                  width: 52.w,
                  height: 52.w,
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    size: 28.sp,
                    color: badgeColor,
                  ),
                ),
                SizedBox(width: 16.w),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2B2D42),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.12),
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
