import 'package:get/get.dart';
import '../services/network/network_controller.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<NetworkController>(NetworkController(), permanent: true);
  }
}
