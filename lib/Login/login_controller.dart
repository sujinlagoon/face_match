import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:http/http.dart' as http;

import '../data/url.dart';
import '../helpers/location_service.dart';
import '../widgets/custom_toast.dart';

class LoginController extends GetxController {
  final formKey = GlobalKey<FormState>();

  TextEditingController usernameController = TextEditingController(text: "LTDEMO111241");
  TextEditingController passwordController = TextEditingController(text: "admin123");

  bool isPasswordHidden = true;
  bool rememberMe = false;
  bool isLoading = false;

  void togglePasswordVisibility() {
    isPasswordHidden = !isPasswordHidden;
    update();
  }

  String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your username or email';
    }
    return null;
  }

  Future<bool> login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty) {
      CustomToast.showError(
        'Please enter your employee ID or username',
      );
      return false;
    }

    if (password.isEmpty) {
      CustomToast.showError('Please enter your password');
      return false;
    }

    try {
      isLoading = true;
      update();

      final locData = await LocationService.getCurrentLocationData();

      final params = {
        'UserName': username,
        'password': password,
        'Loginlat': locData.latitude.toString(),
        'LoginLon': locData.longitude.toString(),
        'LoginLocation': locData.address,
        'deviceImeiNo': '123456',
      };

      final uri = Uri.parse(
        Url.timeKeeperLogin,
      ).replace(
        queryParameters: params,
      );

      debugPrint('Login URL: $uri');

      final req = await http.post(uri);

      debugPrint('[LoginController] Status: ${req.statusCode}, Response: ${req.body}');

      if (req.statusCode == 200) {
        CustomToast.showSuccess('Logged in successfully');

        // You can parse req.body here
        debugPrint('Login response: ${req.body}');
        return true;
      } else {
        CustomToast.showError('Login failed (${req.statusCode})');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('Login error: $e');
      debugPrintStack(stackTrace: stackTrace);

      CustomToast.showError('Something went wrong');
      return false;
    } finally {
      isLoading = false;
      update();
    }
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
