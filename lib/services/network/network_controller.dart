import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../data/url.dart';
import '../offline/offline_punch_store.dart';

/// States for the offline/sync banner matching the Timetick specification.
enum BannerState {
  none,
  offline,
  backOnline,
  syncing,
}

/// Monitors network connectivity and triggers sync of offline punches
/// when the device reconnects.
///
/// Register once in main.dart:
///   `Get.put<NetworkController>(NetworkController(), permanent: true);`
class NetworkController extends GetxController {
  final _connectivity = Connectivity();

  /// Observable — true when the device has a working API connection.
  final isConnected = true.obs;

  /// Current visual state for the bottom banner.
  final bannerState = BannerState.none.obs;

  /// Incremental sync progress: (synced, total).
  final syncedCount = 0.obs;
  final syncTotal = 0.obs;
  final isSyncing = false.obs;
  final allRecordsSynced = false.obs;
  final syncPartialFailure = false.obs;

  /// Reactive count of unsynced offline punches stored locally.
  final pendingCount = 0.obs;

  OfflineSyncResult? _lastSyncResult;
  Timer? _healthCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isReconnecting = false;
  bool _isHealthCheckRunning = false;

  static const Duration _healthCheckInterval = Duration(seconds: 12);
  static const Duration _minSyncBannerDuration = Duration(milliseconds: 1200);

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // Listen for connectivity changes
    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    // Check current state on startup
    _checkInitial();
    // Start periodic health check timer
    _startHealthCheckTimer();
    // Load initial unsynced records count
    refreshPendingOfflineCount();
  }

  @override
  void onClose() {
    _stopHealthCheckTimer();
    _sub?.cancel();
    super.onClose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Formatted subtitle for connection restored banner.
  String get lastSyncBannerSubtitle {
    final result = _lastSyncResult;
    if (result == null || result.noRecords) {
      return 'All attendance records up to date';
    }
    if (result.fullySynced) {
      return 'All ${result.syncedCount} offline record(s) synced to server';
    }
    if (result.stoppedEarly && result.syncedCount == 0) {
      return 'Sync paused — offline records still pending';
    }
    return '${result.syncedCount} of ${result.total} records synced';
  }

  /// Returns true when the device has a link AND the API is reachable.
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        isConnected.value = false;
        return false;
      }
      final reachable = await _pingApi();
      isConnected.value = reachable;
      return reachable;
    } catch (e) {
      isConnected.value = false;
      return false;
    }
  }

  /// Manually triggers sync of unsynced punches if online.
  Future<OfflineSyncResult> syncNow() async {
    if (isSyncing.value) {
      return const OfflineSyncResult(syncedCount: 0, total: 0);
    }
    final online = await checkConnectivity();
    if (!online) {
      _setOfflineState();
      return const OfflineSyncResult(syncedCount: 0, total: 0);
    }
    await _handleBackOnline();
    await refreshPendingOfflineCount();
    return _lastSyncResult ??
        OfflineSyncResult(syncedCount: syncedCount.value, total: syncTotal.value);
  }

  /// Called after an offline punch is recorded to ensure UI is in offline state and refresh pending chips.
  void notifyOfflinePunchSaved() {
    if (!isConnected.value) {
      bannerState.value = BannerState.offline;
    }
    refreshPendingOfflineCount();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkInitial() async {
    final online = await checkConnectivity();
    isConnected.value = online;
    if (kDebugMode) {
      print('[NetworkController] Initial connectivity: $online');
    }
    if (!online) {
      _setOfflineState();
    } else {
      bannerState.value = BannerState.none;
      await _handleBackOnline();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (_isReconnecting) return;

    final hasLink = !results.contains(ConnectivityResult.none);
    if (!hasLink) {
      _setOfflineState();
      if (kDebugMode) print('[NetworkController] 📴 No network link');
      return;
    }

    final reachable = await _pingApi();
    if (!reachable) {
      _setOfflineState();
      return;
    }

    final wasOffline =
        !isConnected.value || bannerState.value == BannerState.offline;
    isConnected.value = true;

    if (wasOffline) {
      if (kDebugMode) {
        print('[NetworkController] 🔄 Back online — syncing offline punches');
      }
      await _handleBackOnline();
    }
  }

  void _setOfflineState() {
    isConnected.value = false;
    bannerState.value = BannerState.offline;
    _startHealthCheckTimer();
  }

  void _startHealthCheckTimer() {
    if (_healthCheckTimer != null) return;
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _runPeriodicHealthCheck();
    });
  }

  void _stopHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _runPeriodicHealthCheck() async {
    if (_isHealthCheckRunning || _isReconnecting) return;
    if (bannerState.value == BannerState.syncing) return;

    _isHealthCheckRunning = true;
    try {
      final wasOnline = isConnected.value;
      final online = await checkConnectivity();

      if (online) {
        if (!wasOnline || bannerState.value == BannerState.offline) {
          await _handleBackOnline();
        } else {
          isConnected.value = true;
        }
      } else {
        if (wasOnline || bannerState.value != BannerState.offline) {
          _setOfflineState();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[NetworkController] Periodic health check error: $e');
      }
    } finally {
      _isHealthCheckRunning = false;
    }
  }

  Future<void> _handleBackOnline() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    try {
      final hasUnsynced = await OfflinePunchStore.hasUnsynced();
      if (hasUnsynced) {
        bannerState.value = BannerState.syncing;
        isSyncing.value = true;
        syncedCount.value = 0;
        syncTotal.value = 0;
        allRecordsSynced.value = false;
        syncPartialFailure.value = false;

        final startedAt = DateTime.now();
        final result = await OfflinePunchStore.syncUnsynced(
          onProgress: (done, total) {
            syncedCount.value = done;
            syncTotal.value = total;
          },
        );

        _lastSyncResult = result;
        syncPartialFailure.value = result.stoppedEarly;

        // Ensure minimum duration so the animation is clearly perceived
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed < _minSyncBannerDuration) {
          await Future.delayed(_minSyncBannerDuration - elapsed);
        }
      } else {
        _lastSyncResult = null;
        allRecordsSynced.value = true;
        if (bannerState.value == BannerState.offline) {
          bannerState.value = BannerState.syncing;
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      bannerState.value = BannerState.backOnline;
      isConnected.value = true;
      isSyncing.value = false;

      // Auto-dismiss backOnline banner after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (isConnected.value && bannerState.value == BannerState.backOnline) {
          bannerState.value = BannerState.none;
          allRecordsSynced.value = false;
          syncPartialFailure.value = false;
        }
      });
    } catch (e) {
      if (kDebugMode) print('[NetworkController] ❌ Sync error: $e');
      try {
        final stillOnline = await _pingApi();
        if (!stillOnline) {
          _setOfflineState();
        } else {
          syncPartialFailure.value = true;
          bannerState.value = BannerState.backOnline;
          isConnected.value = true;
        }
      } catch (_) {
        _setOfflineState();
      }
    } finally {
      isSyncing.value = false;
      _isReconnecting = false;
      await refreshPendingOfflineCount();
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

  /// Manually triggers a reload of the unsynced punches count and updates listeners.
  Future<int> refreshPendingOfflineCount() async {
    final count = await OfflinePunchStore.getUnsyncedCount();
    pendingCount.value = count;
    update(['offline_sync_pending_widget']);
    update();
    return count;
  }
}
