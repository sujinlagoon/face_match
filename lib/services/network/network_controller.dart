import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../data/url.dart';
import '../offline/offline_punch_store.dart';

/// Monitors network connectivity and triggers sync of offline punches
/// when the device reconnects.
///
/// Register once in main.dart:
///   `Get.put<NetworkController>(NetworkController(), permanent: true);`
class NetworkController extends GetxController {
  final _connectivity = Connectivity();

  /// Observable — true when the device has a working API connection.
  final isConnected = true.obs;

  /// Incremental sync progress: (synced, total).
  final syncedCount = 0.obs;
  final syncTotal = 0.obs;
  final isSyncing = false.obs;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isReconnecting = false;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // Listen for connectivity changes
    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    // Check current state on startup
    _checkInitial();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns true when the device has a link AND the API is reachable.
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        isConnected.value = false;
        return false;
      }
      // Quick API ping
      final reachable = await _pingApi();
      isConnected.value = reachable;
      return reachable;
    } catch (e) {
      isConnected.value = false;
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkInitial() async {
    isConnected.value = await checkConnectivity();
    if (kDebugMode) {
      print('[NetworkController] Initial connectivity: ${isConnected.value}');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (_isReconnecting) return;

    final hasLink = !results.contains(ConnectivityResult.none);
    if (!hasLink) {
      isConnected.value = false;
      if (kDebugMode) print('[NetworkController] 📴 No network link');
      return;
    }

    final reachable = await _pingApi();
    if (!reachable) {
      isConnected.value = false;
      return;
    }

    final wasOffline = !isConnected.value;
    isConnected.value = true;

    if (wasOffline) {
      if (kDebugMode) print('[NetworkController] 🔄 Back online — checking unsynced punches');
      await _handleBackOnline();
    }
  }

  Future<void> _handleBackOnline() async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    try {
      final hasUnsynced = await OfflinePunchStore.hasUnsynced();
      if (!hasUnsynced) {
        if (kDebugMode) print('[NetworkController] ✅ No unsynced punches');
        return;
      }

      isSyncing.value = true;
      syncedCount.value = 0;
      syncTotal.value = 0;

      final result = await OfflinePunchStore.syncUnsynced(
        onProgress: (done, total) {
          syncedCount.value = done;
          syncTotal.value = total;
        },
      );

      if (kDebugMode) print('[NetworkController] 🔄 Sync result: $result');
    } catch (e) {
      if (kDebugMode) print('[NetworkController] ❌ Sync error: $e');
    } finally {
      isSyncing.value = false;
      _isReconnecting = false;
    }
  }

  Future<bool> _pingApi() async {
    try {
      final response = await http
          .get(Uri.parse(Url.healthCheck))
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
