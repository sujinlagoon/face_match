import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../helpers/colors.dart';
import '../helpers/routes.dart';
import 'login_controller.dart';
import 'package:face_match/Login/widgets/custom_text_field.dart';

typedef LogiNView = LoginView;

class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LoginController>(
      init: LoginController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 20.h,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Form(
                    key: controller.formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [


                        Center(
                          child: Text(

                            'FaceTick',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Center(
                          child: Text(
                            'Sign in to access your attendance portal',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF6C757D),
                            ),
                          ),
                        ),
                        SizedBox(height: 36.h),

                        CustomTextField(
                          label: 'EMP ID',
                          hint: 'Enter EmployeeID',
                          controller: controller.usernameController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icon(
                            Icons.person_outline_rounded,
                            color: const Color(0xFF6C757D),
                            size: 20.sp,
                          ),
                          validator: controller.validateUsername,
                        ),
                        SizedBox(height: 20.h),

                        CustomTextField(
                          label: 'Password',
                          hint: 'Enter your password',
                          controller: controller.passwordController,
                          obscureText: controller.isPasswordHidden,
                          textInputAction: TextInputAction.done,
                          prefixIcon: Icon(
                            Icons.lock_outline_rounded,
                            color: const Color(0xFF6C757D),
                            size: 20.sp,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              controller.isPasswordHidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF6C757D),
                              size: 20.sp,
                            ),
                            onPressed: controller.togglePasswordVisibility,
                            splashRadius: 20.r,
                          ),
                          //validator: controller.validatePassword,
                        ),
                        SizedBox(height: 24.h),
                        // Login Button
                        SizedBox(
                          height: 52.h,
                          child: ElevatedButton(
                            onPressed: controller.isLoading ? null : () async {
                              bool success = await controller.login();
                              if (success) {
                                Get.toNamed(Routes.mainView);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.primary .withOpacity(0.6),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                            child: controller.isLoading
                                ? SizedBox(
                                    width: 22.w,
                                    height: 22.w,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
