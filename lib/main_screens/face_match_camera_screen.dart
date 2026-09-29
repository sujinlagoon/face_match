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
import 'controller/face_match_controller.dart';
import 'model/profile_face_model.dart';

/// Real-time detected face information for on-screen AR overlay
class RecognizedFaceData {
  final Rect boundingBox;
  final bool isMatched;
  final String? name;
  final String? mobileCode;
  final String? employeeNo;
  final double similarity;

  RecognizedFaceData({
    required this.boundingBox,
    required this.isMatched,
    this.name,
    this.mobileCode,
    this.employeeNo,
    this.similarity = 0.0,
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
  String _statusMessage = "Loading face profiles...";

  // Real-time overlay tracking
  List<RecognizedFaceData> _currentFaces = [];
  Size _lastImageSize = Size.zero;
  final Map<String, EmployeeModel> _matchedEmployeesMap = {};

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

      if (_isProcessingFrame) return;
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
            print("🔥 FACE MATCHED");
            print("🔥 EmployeeNo: ${matchedEmp.employeeNo}");
            print("🔥 Name: ${matchedEmp.name}");
            final key = matchedEmp.employeeNo ??
                matchedEmp.mobileCode ??
                matchedEmp.name ??
                "";

            final isNewMatch = !_matchedEmployeesMap.containsKey(key);
            print("🔥 Match Key: $key");
            print("🔥 Is New Match: $isNewMatch");

            _matchedEmployeesMap[key] = matchedEmp;

            if (isNewMatch) {
              HapticFeedback.lightImpact();

              // ========================================================
              // MATCHED EMPLOYEE -> CHECK STATUS API
              // ========================================================
              print("🔥 CALLING CHECK STATUS API");
              // EmployeeNo is passed to CheckStatus API
              await controller.checkStatusForMatchedEmployee(
                matchedEmp,
              );
              print("🔥 CHECK STATUS FLOW COMPLETED");
            } else {
              print("⚠️ CHECK STATUS SKIPPED - ALREADY MATCHED");
            }



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
    _scannerAnimationController.dispose();
    _pulseAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final matchedList = _matchedEmployeesMap.values.toList();

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "Live Biometric Recognition",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
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

          // 4. Bottom Live Recognition Dock (Non-blocking, Real-Time MobileCode Display)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (matchedList.isNotEmpty)
                      _buildLiveMatchedCarousel(matchedList)
                    else
                      _buildIdleScanningHUD(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a bottom card showcasing the matched employees with their Mobile Code
  Widget _buildLiveMatchedCarousel(List<EmployeeModel> matchedList) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: const Color(0xFF12141A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00E676).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.black),
                ),
                const SizedBox(width: 8),
                const Text(
                  "RECOGNIZED PROFILE",
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Text(
                  "${matchedList.length} Matched",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Horizontal scroll if multiple persons recognized
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: matchedList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final emp = matchedList[index];
                return _buildMatchedProfileCard(emp);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchedProfileCard(EmployeeModel emp) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.black87, size: 26),
          ),
          const SizedBox(width: 12),

          // Info Column with prominent MobileCode
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  emp.name ?? "Employee",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (emp.employeeNo != null)
                  Text(
                    "ID: ${emp.employeeNo}",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(height: 6),

                // Mobile Code Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF00E676),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "MOBILE CODE: ",
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        emp.mobileCode ?? "N/A",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Idle status bar when no face is matched yet
  Widget _buildIdleScanningHUD() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12141A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withOpacity(0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Animated scanner icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.face_retouching_natural_rounded,
              color: Color(0xFF00E5FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Multi-Face Biometric Scanner",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
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
