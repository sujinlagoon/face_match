import 'package:face_match/main_screens/face_match_camera_screen.dart';
import 'package:face_match/main_screens/face_register_screen.dart';
import 'package:face_match/main_screens/main_view.dart';
import 'package:get/get.dart';

import '../Login/login_view.dart';

// import your other views and bindings here


abstract class Routes {
  Routes._();

  static const login = '/login';
  static const timeKeeperDashboard = '/timekeeper-dashboard';
  static const faceRegister = '/face-register';
  static const faceMatch = '/face-match';
  static const mainView = '/main-view';
}



class AppPages {
  AppPages._();

  static const initial = Routes.login;

  static final routes = [
    GetPage(
      name: Routes.login,
      page: () => const LogiNView(),
      // binding: LoginBinding(), // Bind your controller here
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.mainView,
      page: () => const MainView(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.faceRegister,
      page: () => const FaceRegisterScreen(employeeId: 'employeeId'),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: Routes.faceMatch,
      page: () => const FaceMatchCameraScreen(storedEmbedding: [], userKey: ""),
      transition: Transition.rightToLeft,
    ),
  ];
}