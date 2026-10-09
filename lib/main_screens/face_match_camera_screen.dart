import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../helpers/colors.dart';
import '../services/face_service/face_aligner_v2.dart';
import '../services/face_service/face_detector.dart';
import '../services/face_service/face_embedding_v2.dart';
import '../services/face_service/face_matcher_v2.dart';
import '../services/network/network_controller.dart';
import '../widgets/custom_toast.dart';
import 'controller/face_match_controller.dart';
import 'model/profile_face_model.dart';
import 'model/punch_result_model.dart';

/// Real-time detected face information for on-screen AR overlay
class RecognizedFaceData {
  final Rect boundingBox;
  final bool isMatched;
  final String? name;
  final String? mobileCode;
  final String? employeeNo;
  final double similarity;
  final String? punchAction;

  RecognizedFaceData({
    required this.boundingBox,
    required this.isMatched,
    this.name,
    this.mobileCode,
    this.employeeNo,
    this.similarity = 0.0,
    this.punchAction,
  });
}

class FaceMatchCameraScreen extends StatefulWidget {
  final List<double>? storedEmbedding;
  final String userKey;
  final String? timeKeeperId;

  const FaceMatchCameraScreen({
    super.key,
    this.storedEmbedding,
    required this.userKey,
    this.timeKeeperId,
  });

  @override
  State<FaceMatchCameraScreen> createState() => _FaceMatchCameraScreenState();
}

class _FaceMatchCameraScreenState extends State<FaceMatchCameraScreen>
    with TickerProviderStateMixin {
  final FaceMatchController controller = Get.put(FaceMatchController());
  CameraController? _controller;
  bool _isInitializing = true;
  bool _isProcessingFrame = false;
  bool _isMatchLocked = false;
  String _statusMessage = "Loading face profiles...";

  // Real-time overlay tracking
  List<RecognizedFaceData> _currentFaces = [];
  Size _lastImageSize = Size.zero;
  final Map<String, EmployeeModel> _matchedEmployeesMap = {};
  final Map<String, PunchFlowResult> _employeePunchResultMap = {};
  final Map<String, DateTime> _employeeLastPunchTimeMap = {};

  // Active matched employee & punch countdown state
  EmployeeModel? _activeMatchedEmployee;
  PunchAction? _activeAction;
  bool _isPunchOffline = false;
  bool _isPunchLoading = false;
  PunchFlowResult? _completedPunchResult;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;

  late AnimationController _scannerAnimationController;
  late AnimationController _pulseAnimationController;
  Timer? _matchingTimer;

  @override
  void initState() {
    super.initState();
    _scannerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initWorkflow();
  }

  Future<void> _initWorkflow() async {
    // 1. Fetch 1:N profiles from API if not already loaded
    if (widget.storedEmbedding == null || widget.storedEmbedding!.isEmpty) {
      if (controller.employeeList.isEmpty) {
        setState(() {
          _statusMessage = "Fetching registered employees...";
        });

        final targetId = widget.timeKeeperId ?? widget.userKey;
        final success = await controller.faceMatchApi(timeKeeperId: targetId);

        if (!success || controller.employeeList.isEmpty) {
          if (mounted) {
            setState(() {
              _statusMessage = controller.errorMessage ??
                  "No registered faces found for this TimeKeeper.";
            });
          }
        }
      }
    }

    // 2. Initialize Camera
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _statusMessage = controller.employeeList.isNotEmpty
            ? "Multi-Face AI Active • ${controller.employeeList.length} Profiles"
            : "Multi-Face AI Active";
      });

      _startLiveMatchLoop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Camera initialization failed: $e";
          _isInitializing = false;
        });
      }
    }
  }

  void _startLiveMatchLoop() {
    _matchingTimer?.cancel();
    _matchingTimer =
        Timer.periodic(const Duration(milliseconds: 550), (timer) async {
      if (!mounted ||
          _controller == null ||
          !_controller!.value.isInitialized) {
        return;
      }

      if (_isProcessingFrame || _isMatchLocked) return;
      _isProcessingFrame = true;

      File? imageFile;
      try {
        final XFile photo = await _controller!.takePicture();
        imageFile = File(photo.path);

        // 1. Detect all faces in frame & retrieve image dimensions
        final multiDetection = await FaceDetectorService.detectAllFaces(imageFile);
        final detectedFaces = multiDetection.faces;
        final imageSize = multiDetection.imageSize;

        if (detectedFaces.isEmpty) {
          if (mounted && _currentFaces.isNotEmpty) {
            setState(() {
              _currentFaces = [];
            });
          }
          return;
        }

        final List<RecognizedFaceData> frameOverlays = [];

        // 2. Process each detected face concurrently in real-time
        for (final face in detectedFaces) {
          final aligned = await FaceAlignerV2.alignFaceV2(
            multiDetection.normalizedImageFile,
            face,
          );

          if (aligned == null) {
            frameOverlays.add(
              RecognizedFaceData(
                boundingBox: face.boundingBox,
                isMatched: false,
              ),
            );
            continue;
          }

          // Extract 512-d live embedding
          final liveEmbedding =
              await FaceEmbeddingServiceV2.getEmbedding(aligned);

          EmployeeModel? matchedEmp;
          double bestSimilarity = 0.0;

          // Mode A: Single 1:1 match if storedEmbedding was passed directly
          if (widget.storedEmbedding != null &&
              widget.storedEmbedding!.isNotEmpty) {
            final result = FaceMatcherV2.verifyFace(
              liveEmbedding: liveEmbedding,
              storedEmbedding: widget.storedEmbedding!,
            );
            bestSimilarity = result.similarity;
            if (result.matched) {
              matchedEmp = EmployeeModel(
                name: "Employee",
                employeeNo: widget.userKey,
                mobileCode: widget.userKey,
              );
            }
          } else {
            // Mode B: 1:N Multi-Face recognition across all employee profiles
            final matchResult =
                controller.matchLiveEmbedding(liveEmbedding);
            if (matchResult != null) {
              bestSimilarity = matchResult.similarity;
              matchedEmp = matchResult.employee;
            }
          }

          if (matchedEmp != null) {
            // ── Lock further matches immediately ────────────────────────────
            _isMatchLocked = true;

            print("🔥 FACE MATCHED");
            print("🔥 EmployeeNo: ${matchedEmp.employeeNo}");
            print("🔥 Name: ${matchedEmp.name}");
            final key = matchedEmp.effectiveEmployeeNo.isNotEmpty
                ? matchedEmp.effectiveEmployeeNo
                : (matchedEmp.name ?? "");

            final lastPunchTime = _employeeLastPunchTimeMap[key];
            final now = DateTime.now();
            final bool isWithinCooldown = lastPunchTime != null &&
                now.difference(lastPunchTime).inSeconds < 5;

            if (isWithinCooldown) {
              _isMatchLocked = false;
              break;
            }

            _matchedEmployeesMap[key] = matchedEmp;

            frameOverlays.add(
              RecognizedFaceData(
                boundingBox: face.boundingBox,
                isMatched: true,
                name: matchedEmp.name,
                mobileCode: matchedEmp.mobileCode,
                employeeNo: matchedEmp.employeeNo,
                similarity: bestSimilarity,
              ),
            );

            // Step 1: Look for match -> matched! Lock flow & set full-width card initial state
            if (mounted) {
              setState(() {
                _activeMatchedEmployee = matchedEmp;
                _activeAction = null;
                _isPunchLoading = true;
                _completedPunchResult = null;
                _countdownSeconds = 5;
                _currentFaces = frameOverlays;
                if (imageSize.width > 0 && imageSize.height > 0) {
                  _lastImageSize = imageSize;
                }
                _statusMessage =
                    "Resolving status for ${matchedEmp?.name ?? 'Employee'}...";
              });
            }

            PunchFlowResult? punchResult;
            try {
              HapticFeedback.lightImpact();

              // ========================================================
              // Step 2 & 3: Get checkstatus -> show UI (checking in or out with loader)
              // Step 4: API call (newInOut / storePunch)
              // ========================================================
              print("🔥 CALLING CHECK STATUS & CHECKINOUT API FOR $key");
              punchResult = await controller.checkStatusForMatchedEmployee(
                matchedEmp,
                onStatusResolved: (PunchAction action, bool isOffline) {
                  if (mounted) {
                    setState(() {
                      _activeAction = action;
                      _isPunchOffline = isOffline;
                      _isPunchLoading = true;
                      final actionLabel = action == PunchAction.checkIn
                          ? "Checking In"
                          : "Checking Out";
                      _statusMessage =
                          "$actionLabel: ${matchedEmp?.name ?? 'Employee'}...";
                    });
                  }
                },
              );
              print(
                "🔥 CHECK STATUS & CHECKINOUT FLOW COMPLETED: ${punchResult.actionLabel}",
              );

              if (punchResult.success && punchResult.action != null) {
                _employeePunchResultMap[key] = punchResult;
                _employeeLastPunchTimeMap[key] = DateTime.now();
                _completedPunchResult = punchResult;
                _activeAction = punchResult.action;
                _isPunchOffline = punchResult.isOffline;
                _isPunchLoading = false;

                final action = punchResult.actionLabel;
                if (punchResult.isOffline) {
                  HapticFeedback.heavyImpact();
                  _statusMessage =
                      "📴 ${matchedEmp.name ?? 'Employee'} $action • ${punchResult.formattedTime} (Saved Offline)";
                  CustomToast.showSuccess(
                    "Offline Punch Saved: ${matchedEmp.name ?? 'Employee'} $action (Saved to local device)",
                  );
                } else {
                  HapticFeedback.lightImpact();
                  _statusMessage =
                      "✅ ${matchedEmp.name ?? 'Employee'} $action • ${punchResult.formattedTime} (Synced Online)";
                  CustomToast.showSuccess(
                    "${matchedEmp.name ?? 'Employee'} $action (Synced Online)",
                  );
                }
              } else {
                _isPunchLoading = false;
                _completedPunchResult = punchResult;
                _statusMessage = punchResult.message ?? "Punch failed";
              }
            } catch (e) {
              debugPrint("❌ Error in checkStatusForMatchedEmployee: $e");
              punchResult = PunchFlowResult(
                success: false,
                timestamp: DateTime.now(),
                employeeNo: key,
                employeeName: matchedEmp.name ?? "Employee",
                message: e.toString(),
              );
              _isPunchLoading = false;
              _completedPunchResult = punchResult;
            } finally {
              if (mounted) {
                setState(() {
                  _isPunchLoading = false;
                });
              }

              // ========================================================
              // Step 5: Lock release with a 5-second countdown delay:
              // "Punch available in $countdown seconds"
              // ========================================================
              _countdownSeconds = 5;
              _countdownTimer?.cancel();
              final completer = Completer<void>();
              _countdownTimer = Timer.periodic(
                const Duration(seconds: 1),
                (timer) {
                  if (!mounted) {
                    timer.cancel();
                    if (!completer.isCompleted) completer.complete();
                    return;
                  }
                  setState(() {
                    _countdownSeconds--;
                  });
                  if (_countdownSeconds <= 0) {
                    timer.cancel();
                    if (!completer.isCompleted) completer.complete();
                  }
                },
              );

              await completer.future;

              if (mounted) {
                setState(() {
                  _activeMatchedEmployee = null;
                  _activeAction = null;
                  _completedPunchResult = null;
                  _isPunchLoading = false;
                  _countdownSeconds = 5;
                  _currentFaces = [];
                  _statusMessage = controller.employeeList.isNotEmpty
                      ? "Multi-Face AI Active • ${controller.employeeList.length} Profiles"
                      : "Multi-Face AI Active";
                });
              }

              _isMatchLocked = false;
            }

            break; // Stop evaluating remaining faces in this frame
          }
        }

        if (mounted) {
          setState(() {
            _currentFaces = frameOverlays;
            if (imageSize.width > 0 && imageSize.height > 0) {
              _lastImageSize = imageSize;
            }
          });
        }
      } catch (e) {
        debugPrint("[FaceMatchCameraScreen] Frame processing error: $e");
      } finally {
        if (imageFile != null && await imageFile.exists()) {
          try {
            await imageFile.delete();
          } catch (_) {}
        }
        _isProcessingFrame = false;
      }
    });
  }

  @override
  void dispose() {
    _matchingTimer?.cancel();
    _countdownTimer?.cancel();
    _scannerAnimationController.dispose();
    _pulseAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Builder(
          builder: (_) {
            if (!Get.isRegistered<NetworkController>()) {
              return const Text(
                "Live Biometric Recognition",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              );
            }
            final netCtrl = Get.find<NetworkController>();
            return Obx(() {
              final isOnline = netCtrl.isConnected.value;
              final isSyncing = netCtrl.isSyncing.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF9100),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isSyncing
                        ? "Syncing Punches..."
                        : (isOnline
                            ? "Live Biometric Recognition"
                            : "Offline Biometric Mode"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              );
            });
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (Get.isRegistered<NetworkController>())
            Obx(() {
              final netCtrl = Get.find<NetworkController>();
              final isSyncing = netCtrl.isSyncing.value;
              return IconButton(
                icon: isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                tooltip: "Sync Offline Punches",
                onPressed: isSyncing
                    ? null
                    : () async {
                        final res = await netCtrl.syncNow();
                        if (res.syncedCount > 0) {
                          CustomToast.showSuccess("Synced ${res.syncedCount} punch(es)");
                        } else if (!netCtrl.isConnected.value) {
                          CustomToast.showError("Device is offline");
                        } else {
                          CustomToast.showSuccess("All punches up to date");
                        }
                      },
              );
            }),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Preview (Fullscreen Cover)
          if (!_isInitializing &&
              _controller != null &&
              _controller!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 100,
                  height: 100 * _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),

          if (_isInitializing)
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),

          // 2. Real-Time AR Face Overlays Painter
          if (!_isInitializing && _currentFaces.isNotEmpty)
            AnimatedBuilder(
              animation: _scannerAnimationController,
              builder: (context, _) {
                return CustomPaint(
                  size: screenSize,
                  painter: FaceOverlayPainter(
                    faces: _currentFaces,
                    imageSize: _lastImageSize,
                    screenSize: screenSize,
                    scanProgress: _scannerAnimationController.value,
                    isFrontCamera: true,
                  ),
                );
              },
            ),

          // 3. Top Floating Status HUD
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _currentFaces.any((f) => f.isMatched)
                          ? Icons.check_circle_rounded
                          : Icons.center_focus_weak_rounded,
                      color: _currentFaces.any((f) => f.isMatched)
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00E5FF),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _currentFaces.isEmpty
                          ? "Detecting faces..."
                          : "${_currentFaces.length} face(s) in view",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (controller.employeeList.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        "• ${controller.employeeList.length} registered",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Live Recognition Dock (Full-Width Matched Employee Flow or Scanning HUD)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _activeMatchedEmployee != null
                      ? _buildFullWidthPunchCard(_activeMatchedEmployee!)
                      : _buildIdleScanningHUD(),
                ),
              ),
            ),
          ),

          // 5. Persistent Offline Pill on Camera View
          if (Get.isRegistered<NetworkController>())
            Obx(() {
              final isOnline = Get.find<NetworkController>().isConnected.value;
              if (isOnline) return const SizedBox.shrink();
              return SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, right: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        SizedBox(width: 5),
                        Text(
                          "OFFLINE MODE",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Builds a full-width bottom card showcasing the matched employee,
  /// checking in/out status with an animated loader, punch confirmation, and 5-second countdown.
  Widget _buildFullWidthPunchCard(EmployeeModel emp) {
    final bool isOffline = _isPunchOffline ||
        (Get.isRegistered<NetworkController>() &&
            !Get.find<NetworkController>().isConnected.value);

    final isCheckIn = _activeAction == PunchAction.checkIn;
    final isCheckOut = _activeAction == PunchAction.checkOut;
    final Color actionColor = isCheckIn
        ? const Color(0xFF00E676)
        : (isCheckOut ? const Color(0xFFFF9100) : const Color(0xFF00E5FF));

    final punchResult = _completedPunchResult;
    final bool isCompleted = punchResult != null;
    final bool isSuccess = isCompleted && punchResult.success;
    final bool isFailure = isCompleted && !punchResult.success;
    final bool isLoading = _isPunchLoading;

    final image = emp.userImage ?? emp.regImage;

    return Container(
      key: ValueKey("punch_card_${emp.employeeNo ?? emp.mobileCode ?? emp.name}"),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10131B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (isFailure ? const Color(0xFFFF5252) : actionColor)
              .withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isFailure ? const Color(0xFFFF5252) : actionColor)
                .withValues(alpha: 0.22),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Bar ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isFailure
                      ? const Color(0xFFFF5252)
                      : (isSuccess
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00E5FF)),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isFailure
                              ? const Color(0xFFFF5252)
                              : (isSuccess
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF00E5FF)))
                          .withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isSuccess
                    ? "ATTENDANCE RECORDED"
                    : (isFailure
                        ? "ATTENDANCE ERROR"
                        : "MATCH VERIFIED • ATTENDANCE FLOW"),
                style: TextStyle(
                  color: isFailure
                      ? const Color(0xFFFF5252)
                      : (isSuccess
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00E5FF)),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              // Network indicator pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isOffline
                      ? const Color(0xFFFF9100).withValues(alpha: 0.16)
                      : const Color(0xFF00E676).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isOffline
                        ? const Color(0xFFFF9100).withValues(alpha: 0.5)
                        : const Color(0xFF00E676).withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOffline
                          ? Icons.cloud_off_rounded
                          : Icons.cloud_done_rounded,
                      size: 11,
                      color: isOffline
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFF00E676),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOffline ? "OFFLINE" : "ONLINE",
                      style: TextStyle(
                        color: isOffline
                            ? const Color(0xFFFFB74D)
                            : const Color(0xFF00E676),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // ── Matched Employee Info ───────────────────────────────────
          Row(
            children: [
              // Avatar with gradient glow
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      actionColor,
                      actionColor.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: actionColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: (image != null &&
                          image.isNotEmpty &&
                          image.startsWith('http'))
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.person_rounded,
                            color: Colors.black87,
                            size: 30,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: Colors.black87,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // Details column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emp.name ?? "Employee",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (emp.effectiveEmployeeNo.isNotEmpty)
                          Text(
                            "ID: ${emp.effectiveEmployeeNo}",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (emp.department != null &&
                            emp.department!.isNotEmpty) ...[
                          Text(
                            " • ${emp.department}",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    if (emp.mobileCode != null &&
                        emp.mobileCode!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: actionColor.withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          "CODE: ${emp.mobileCode}",
                          style: TextStyle(
                            color: actionColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Flow State & Action Status ──────────────────────────────
          if (isLoading)
            // State: Checking in or out with animated loader
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: actionColor.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCheckIn
                        ? Icons.login_rounded
                        : (isCheckOut
                            ? Icons.logout_rounded
                            : Icons.hourglass_top_rounded),
                    color: actionColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCheckIn
                              ? "CHECKING IN..."
                              : (isCheckOut
                                  ? "CHECKING OUT..."
                                  : "RESOLVING STATUS..."),
                          style: TextStyle(
                            color: actionColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          isOffline
                              ? "Storing offline biometric punch..."
                              : "Sending attendance punch to server...",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(actionColor),
                    ),
                  ),
                ],
              ),
            )
          else if (isSuccess)
            // State: Checked in or out confirmation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: actionColor.withValues(alpha: 0.75),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: actionColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCheckIn
                              ? "CHECKED IN SUCCESSFULLY"
                              : "CHECKED OUT SUCCESSFULLY",
                          style: TextStyle(
                            color: actionColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${punchResult.formattedTime} • ${punchResult.isOffline ? 'Saved locally (auto-syncs)' : 'Synced Online'}",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (isFailure)
            // State: Error
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.75),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFFF5252),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "PUNCH FAILED",
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          punchResult.message ?? "Please try again",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── Countdown Delay (5 seconds) ─────────────────────────────
          // "then for the delay(make it 5 seconds) -> Punch available in $countdown seconds. something like that."
          if (!isLoading) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: actionColor,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        "Punch available in $_countdownSeconds ${_countdownSeconds == 1 ? 'second' : 'seconds'}",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "$_countdownSeconds s",
                        style: TextStyle(
                          color: actionColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _countdownSeconds / 5.0,
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(actionColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Idle status bar when no face is matched yet
  Widget _buildIdleScanningHUD() {
    final bool isOffline = Get.isRegistered<NetworkController>() &&
        !Get.find<NetworkController>().isConnected.value;

    final themeColor = isOffline
        ? const Color(0xFFFF9100)
        : const Color(0xFF00E5FF);

    return Container(
      key: const ValueKey("idle_hud"),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12141A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Animated scanner icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOffline
                  ? Icons.cloud_off_rounded
                  : Icons.face_retouching_natural_rounded,
              color: themeColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isOffline
                          ? "Offline Biometric Scanner"
                          : "Multi-Face Biometric Scanner",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOffline) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9100).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "OFFLINE",
                          style: TextStyle(
                            color: Color(0xFFFFB74D),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders high-tech AR biometric corner brackets
/// and floating info tags directly over each detected face on screen.
class FaceOverlayPainter extends CustomPainter {
  final List<RecognizedFaceData> faces;
  final Size imageSize;
  final Size screenSize;
  final double scanProgress;
  final bool isFrontCamera;

  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.screenSize,
    required this.scanProgress,
    this.isFrontCamera = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty || imageSize.width == 0 || imageSize.height == 0) return;

    // Calculate BoxFit.cover scale and offsets
    final double scaleX = screenSize.width / imageSize.width;
    final double scaleY = screenSize.height / imageSize.height;
    final double scale = math.max(scaleX, scaleY);
    final double offsetX = (screenSize.width - imageSize.width * scale) / 2;
    final double offsetY = (screenSize.height - imageSize.height * scale) / 2;

    for (final face in faces) {
      final rect = face.boundingBox;

      // Transform image boundingBox to screen coordinates (with front-camera mirror flip)
      final double left;
      final double right;
      if (isFrontCamera) {
        left = screenSize.width - (rect.right * scale + offsetX);
        right = screenSize.width - (rect.left * scale + offsetX);
      } else {
        left = rect.left * scale + offsetX;
        right = rect.right * scale + offsetX;
      }
      final double top = rect.top * scale + offsetY;
      final double bottom = rect.bottom * scale + offsetY;

      final screenRect = Rect.fromLTRB(left, top, right, bottom);

      final Color primaryColor = face.isMatched
          ? const Color(0xFF00E676) // Emerald Green for matched
          : const Color(0xFF00E5FF); // Electric Cyan for scanning

      // 1. Draw Subtle Translucent Tint inside face area
      final fillPaint = Paint()
        ..color = primaryColor.withOpacity(face.isMatched ? 0.08 : 0.04)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(screenRect, const Radius.circular(16)),
        fillPaint,
      );

      // 2. Draw Futuristic Corner Brackets
      _drawCornerBrackets(canvas, screenRect, primaryColor);

      // 3. Draw Animated Scanning Line for unverified faces
      if (!face.isMatched) {
        _drawScanLine(canvas, screenRect, primaryColor);
      }

      // 4. Draw Floating AR Tag (Name + MobileCode)
      _drawFloatingTag(canvas, screenRect, face, primaryColor);
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final bracketPaint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double cornerLen = math.min(rect.width, rect.height) * 0.22;

    // Top-Left
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left + cornerLen, rect.top), bracketPaint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left, rect.top + cornerLen), bracketPaint);

    // Top-Right
    canvas.drawLine(
        Offset(rect.right, rect.top), Offset(rect.right - cornerLen, rect.top), bracketPaint);
    canvas.drawLine(
        Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerLen), bracketPaint);

    // Bottom-Left
    canvas.drawLine(
        Offset(rect.left, rect.bottom), Offset(rect.left + cornerLen, rect.bottom), bracketPaint);
    canvas.drawLine(
        Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - cornerLen), bracketPaint);

    // Bottom-Right
    canvas.drawLine(
        Offset(rect.right, rect.bottom), Offset(rect.right - cornerLen, rect.bottom), bracketPaint);
    canvas.drawLine(
        Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - cornerLen), bracketPaint);
  }

  void _drawScanLine(Canvas canvas, Rect rect, Color color) {
    final double y = rect.top + (rect.height * scanProgress);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.8),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTRB(rect.left, y - 2, rect.right, y + 2))
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(rect.left + 8, y), Offset(rect.right - 8, y), scanPaint);
  }

  void _drawFloatingTag(
      Canvas canvas, Rect rect, RecognizedFaceData face, Color color) {
    final String titleText;
    final String? subtitleText;

    if (face.isMatched) {
      titleText = "✓ ${face.name ?? 'Verified'}";
      subtitleText = "Mobile: ${face.mobileCode ?? 'N/A'}";
    } else {
      titleText = "Scanning Face...";
      subtitleText = null;
    }

    final TextSpan span = TextSpan(
      children: [
        TextSpan(
          text: "$titleText\n",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitleText != null)
          TextSpan(
            text: subtitleText,
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
      ],
    );

    final textPainter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final double padX = 12;
    final double padY = 6;
    final double tagWidth = textPainter.width + padX * 2;
    final double tagHeight = textPainter.height + padY * 2;

    // Position floating tag right above the face frame
    double tagLeft = rect.center.dx - (tagWidth / 2);
    double tagTop = rect.top - tagHeight - 12;

    // Flip below face frame if too close to screen top
    if (tagTop < 80) {
      tagTop = rect.bottom + 12;
    }

    final tagRect =
        Rect.fromLTWH(tagLeft, tagTop, tagWidth, tagHeight);

    // Pill Background
    final bgPaint = Paint()
      ..color = const Color(0xFF12141A).withOpacity(0.88)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, const Radius.circular(10)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, const Radius.circular(10)),
      borderPaint,
    );

    // Paint Text
    textPainter.paint(canvas, Offset(tagLeft + padX, tagTop + padY));
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.faces != faces;
  }
}
