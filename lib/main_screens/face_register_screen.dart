import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:face_match/services/face_service/face_aligner_v2.dart';
import 'package:face_match/services/face_service/face_embedding_v2.dart';
import 'package:face_match/services/face_service/face_service_v2.dart';
import 'package:face_match/helpers/colors.dart';
import 'package:flutter/material.dart';
import '../services/face_service/face_detector.dart';
import '../widgets/custom_toast.dart';

class FaceRegisterScreen extends StatefulWidget {
  final String? employeeId;

  const FaceRegisterScreen({
    super.key,
    this.employeeId,
  });

  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isInitializing = true;

  bool loading = false;
  String statusStep = "Ready for registration";
  double currentProgress = 0.0;
  File? capturedImage;

  final TextEditingController _employeeIdController = TextEditingController(text:"LTDEMO000910014");
  final FocusNode _employeeIdFocusNode = FocusNode();
  String? _employeeIdError;

  late AnimationController _scanAnimationController;
  late AnimationController _pulseAnimationController;

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initCamera();
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

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      print("[FaceRegisterScreen] Camera initialization failed: $e");
      if (mounted) {
        setState(() {
          _isInitializing = false;
          statusStep = "Camera initialization failed.";
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scanAnimationController.dispose();
    _pulseAnimationController.dispose();
    _employeeIdController.dispose();
    _employeeIdFocusNode.dispose();
    super.dispose();
  }

  Future<void> registerFace() async {
    final enteredId = _employeeIdController.text.trim();
    if (enteredId.isEmpty) {
      setState(() {
        _employeeIdError = "Please enter Employee ID";
      });
      _employeeIdFocusNode.requestFocus();
      if (mounted) {
        CustomToast.showError(
          "Please enter Employee ID before scanning.",
          context: context,
        );
      }
      return;
    }

    if (_controller == null || !_controller!.value.isInitialized || loading) {
      return;
    }

    FocusScope.of(context).unfocus();

    print("[FaceRegisterScreen] Starting registerFace for employeeId/userKey: '$enteredId'");

    if (mounted) {
      setState(() {
        _employeeIdError = null;
        loading = true;
        capturedImage = null;
        statusStep = "Capturing image...";
        currentProgress = 0.15;
      });
      _scanAnimationController.repeat(reverse: true);
    }

    try {
      // Capture frame directly from live camera stream embedded on screen
      final XFile photo = await _controller!.takePicture();
      final photoFile = File(photo.path);

      if (mounted) {
        setState(() {
          capturedImage = photoFile;
          statusStep = "Detecting face...";
          currentProgress = 0.35;
        });
      }

      await Future.delayed(const Duration(milliseconds: 100));

      //---------------------------------------
      // Detect Face
      //---------------------------------------
      print("[FaceRegisterScreen] Running FaceDetectorService.detectFace...");
      final detection = await FaceDetectorService.detectFace(capturedImage!);
      print(
          "[FaceRegisterScreen] Detection Status: ${detection.status}, BoundingBox: ${detection.face?.boundingBox}");

      if (detection.status != FaceDetectionStatus.success) {
        print(
            "[FaceRegisterScreen] ❌ Face detection failed: ${detection.message}");
        CustomToast.showError(
          detection.message ?? "No face detected in image.",
          context: context,
        );
        if (mounted) {
          setState(() {
            loading = false;
            capturedImage = null;
            currentProgress = 0.0;
            statusStep = "No face detected. Please try again.";
          });
          _scanAnimationController.stop();
        }
        return;
      }

      //---------------------------------------
      // Face Quality Validation
      //---------------------------------------
      final validationMsg = FaceDetectorService.validateFace(detection.face!);
      if (validationMsg != null) {
        print(
            "[FaceRegisterScreen] ❌ Face quality validation failed: $validationMsg");
        CustomToast.showError(
          validationMsg,
          context: context,
        );
        if (mounted) {
          setState(() {
            loading = false;
            capturedImage = null;
            currentProgress = 0.0;
            statusStep = validationMsg;
          });
          _scanAnimationController.stop();
        }
        return;
      }

      if (mounted) {
        setState(() {
          statusStep = "Processing face model...";
          currentProgress = 0.65;
        });
      }
      await Future.delayed(const Duration(milliseconds: 150));

      //---------------------------------------
      // Align Face
      //---------------------------------------
      print("[FaceRegisterScreen] Aligning face image to 160x160...");
      final alignedFace = await FaceAlignerV2.alignFaceV2(
        detection.normalizedImageFile ?? capturedImage!,
        detection.face!,
      );

      if (alignedFace == null) {
        print("[FaceRegisterScreen] ❌ Face aligner returned null");
        CustomToast.showError(
          "Unable to process face features.",
          context: context,
        );
        if (mounted) {
          setState(() {
            loading = false;
            capturedImage = null;
            currentProgress = 0.0;
            statusStep = "Unable to process face features.";
          });
          _scanAnimationController.stop();
        }
        return;
      }

      //---------------------------------------
      // Generate Embedding
      //---------------------------------------
      print("[FaceRegisterScreen] Generating 512-d embedding with FaceNet...");
      final embedding = await FaceEmbeddingServiceV2.getEmbedding(alignedFace);
      print(
          "[FaceRegisterScreen] Generated embedding vector size: ${embedding.length}");
      print(
          "[FaceRegisterScreen] 📊 Full Embedding Vector Points (${embedding.length} values): $embedding");

      if (mounted) {
        setState(() {
          statusStep = "Saving face registration...";
          currentProgress = 0.90;
        });
      }
      await Future.delayed(const Duration(milliseconds: 150));

      //---------------------------------------
      // Convert Raw Photo to Base64 (RealFace)
      //---------------------------------------
      String? base64Photo;
      try {
        final rawFile = capturedImage ?? photoFile;
        final imageBytes = await rawFile.readAsBytes();
        base64Photo = base64Encode(imageBytes);
        print(
            "[FaceRegisterScreen] Converted raw photo to Base64 (${base64Photo.length} chars)");
      } catch (e) {
        print("[FaceRegisterScreen] Error converting raw photo to Base64: $e");
      }

      //---------------------------------------
      // Save Embedding via FaceService API & Cache
      //---------------------------------------
      print(
          "[FaceRegisterScreen] Registering face embedding for '$enteredId' via FaceService...");
      final saved = await FaceServiceV2.registerFace(
        employeeId: enteredId,
        faceEmbedding: embedding,
        realFace: base64Photo,
      );

      print("[FaceRegisterScreen] FaceService.registerFace returned: $saved");

      if (!saved) {
        print(
            "[FaceRegisterScreen] ❌ Failed to save face registration to storage");
        CustomToast.showError(
          "Failed to save face registration. Please try again.",
          context: context,
        );
        if (mounted) {
          setState(() {
            loading = false;
            capturedImage = null;
            currentProgress = 0.0;
            statusStep = "Failed to save. Please try again.";
          });
          _scanAnimationController.stop();
        }
        return;
      }

      if (mounted) {
        setState(() {
          currentProgress = 1.0;
          statusStep = "Face Registered Successfully!";
        });
      }
      await Future.delayed(const Duration(milliseconds: 400));

      print(
          "[FaceRegisterScreen] ✅ Face registered successfully for '$enteredId'! Popping back...");

      CustomToast.showSuccess(
        "Face registered successfully!",
        context: context,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      CustomToast.showError(
        e.toString(),
        context: context,
      );
      if (mounted) {
        setState(() {
          loading = false;
          capturedImage = null;
          currentProgress = 0.0;
          statusStep = "Error during registration.";
        });
        _scanAnimationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppColors.primary;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        //backgroundColor: AppColors.primaryLight,
        appBar: AppBar(
          title: const Text(
            "Face Registration",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: primaryColor,
          centerTitle: true,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Biometric Face Scan",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Position your face inside the mask overlay to scan & register.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color:Colors.grey
                   
                  ),
                ),
                const SizedBox(height: 20),

                // Embedded Camera Viewport with Face Mask, Laser & Outer Progress Ring
                _buildFaceViewport(primaryColor),
                const SizedBox(height: 20),

                // Progress Card or Guidance Tips
                if (loading) ...[
                  _buildProgressCard(primaryColor),
                ] else ...[
                  _buildGuidanceTips(primaryColor),
                ],

                const SizedBox(height: 20),

                // Manual Employee ID Input Field
                _buildEmployeeIdField(primaryColor),

                const SizedBox(height: 24),

                // Action button
                if (!loading) _buildActionButton(primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaceViewport(Color primaryColor) {
    if (_isInitializing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Container(
        height: 330,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              const Text(
                "Initializing Camera...",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 330,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Embedded Live Camera Stream or Captured Freeze Frame
            Positioned.fill(
              child: capturedImage != null
                  ? Image.file(
                      capturedImage!,
                      fit: BoxFit.cover,
                    )
                  : FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.previewSize?.height ?? 1,
                        height: _controller!.value.previewSize?.width ?? 1,
                        child: CameraPreview(_controller!),
                      ),
                    ),
            ),

            // Face Mask Shroud Overlay & Corner Reticles
            AnimatedBuilder(
              animation: _pulseAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _FaceMaskOverlayPainter(
                    primaryColor: primaryColor,
                    pulseValue: _pulseAnimationController.value,
                  ),
                );
              },
            ),

            // Outer Progress Ring
            CustomPaint(
              size: Size.infinite,
              painter: _ProgressRingPainter(
                progress: currentProgress,
                primaryColor: primaryColor,
              ),
            ),

            // Animated Laser Scan Line
            if (loading)
              AnimatedBuilder(
                animation: _scanAnimationController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _ScanLinePainter(
                      scanValue: _scanAnimationController.value,
                      primaryColor: primaryColor,
                    ),
                  );
                },
              ),

            // Percentage Badge top-right
            if (loading)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primaryColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${(currentProgress * 100).toInt()}%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(Color primaryColor) {
    IconData stepIcon;
    if (currentProgress < 0.3) {
      stepIcon = Icons.center_focus_weak_rounded;
    } else if (currentProgress < 0.7) {
      stepIcon = Icons.psychology_rounded;
    } else if (currentProgress < 1.0) {
      stepIcon = Icons.cloud_upload_rounded;
    } else {
      stepIcon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  stepIcon,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        statusStep,
                        key: ValueKey<String>(statusStep),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Please hold your device steady",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "${(currentProgress * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              tween: Tween<double>(begin: 0, end: currentProgress),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: primaryColor.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceTips(Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildTipChip(Icons.wb_sunny_outlined, "Good Light", primaryColor),
        _buildTipChip(Icons.center_focus_strong, "Centered", primaryColor),
        _buildTipChip(
            Icons.visibility_outlined, "Look Straight", primaryColor),
      ],
    );
  }

  Widget _buildTipChip(IconData icon, String label, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: primaryColor.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: registerFace,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.center_focus_strong_rounded,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Text(
              "Scan & Register Face",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeIdField(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _employeeIdController,
        focusNode: _employeeIdFocusNode,
        enabled: !loading,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        onChanged: (val) {
          if (_employeeIdError != null) {
            setState(() {
              _employeeIdError = null;
            });
          } else {
            setState(() {});
          }
        },
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E2022),
          letterSpacing: 0.5,
        ),
        decoration: InputDecoration(
          labelText: "Employee ID",
          labelStyle: TextStyle(
            color: _employeeIdError != null ? Colors.red : Colors.grey[700],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          hintText: "Enter Employee ID (e.g. EMP1024)",
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
          errorText: _employeeIdError,
          prefixIcon: Icon(
            Icons.badge_outlined,
            color: _employeeIdError != null ? Colors.red : primaryColor,
            size: 22,
          ),
          suffixIcon: _employeeIdController.text.isNotEmpty && !loading
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 20,
                    color: Colors.grey,
                  ),
                  onPressed: () {
                    _employeeIdController.clear();
                    setState(() {
                      _employeeIdError = null;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: loading ? const Color(0xFFF5F5F5) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFE4E7EC),
              width: 1.2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _employeeIdError != null
                  ? Colors.red
                  : const Color(0xFFE4E7EC),
              width: 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: primaryColor,
              width: 1.8,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Colors.red,
              width: 1.4,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Colors.red,
              width: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceMaskOverlayPainter extends CustomPainter {
  final Color primaryColor;
  final double pulseValue;

  _FaceMaskOverlayPainter({
    required this.primaryColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final ovalWidth = size.width * 0.65;
    final ovalHeight = size.height * 0.74;
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // 1. Dark overlay outside the face mask oval
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()..addRect(rect);
    final ovalPath = Path()..addOval(ovalRect);
    final combinedPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    canvas.drawPath(combinedPath, overlayPaint);

    // 2. Pulsing glow around oval boundary
    final pulseGlowPaint = Paint()
      ..color = primaryColor.withOpacity(0.25 + 0.25 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + 4 * pulseValue
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawOval(ovalRect, pulseGlowPaint);

    // 3. Inner border line
    final borderPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawOval(ovalRect, borderPaint);

    // 4. Biometric Corner Reticle Brackets (4 Corners)
    const bracketLength = 22.0;
    final bracketPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final left = ovalRect.left - 6;
    final right = ovalRect.right + 6;
    final top = ovalRect.top - 6;
    final bottom = ovalRect.bottom + 6;

    // Top-Left corner
    canvas.drawLine(
        Offset(left, top + bracketLength), Offset(left, top), bracketPaint);
    canvas.drawLine(
        Offset(left, top), Offset(left + bracketLength, top), bracketPaint);

    // Top-Right corner
    canvas.drawLine(
        Offset(right - bracketLength, top), Offset(right, top), bracketPaint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + bracketLength), bracketPaint);

    // Bottom-Left corner
    canvas.drawLine(Offset(left, bottom - bracketLength), Offset(left, bottom),
        bracketPaint);
    canvas.drawLine(
        Offset(left, bottom), Offset(left + bracketLength, bottom), bracketPaint);

    // Bottom-Right corner
    canvas.drawLine(Offset(right - bracketLength, bottom),
        Offset(right, bottom), bracketPaint);
    canvas.drawLine(Offset(right, bottom),
        Offset(right, bottom - bracketLength), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant _FaceMaskOverlayPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}

class _ScanLinePainter extends CustomPainter {
  final double scanValue; // 0.0 to 1.0
  final Color primaryColor;

  _ScanLinePainter({
    required this.scanValue,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalWidth = size.width * 0.65;
    final ovalHeight = size.height * 0.74;
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    final lineY = ovalRect.top + ovalHeight * scanValue;

    canvas.save();
    canvas.clipPath(Path()..addOval(ovalRect));

    // Glow beam rectangle around scan line
    const beamHeight = 28.0;
    final beamRect = Rect.fromLTRB(
      ovalRect.left,
      lineY - beamHeight / 2,
      ovalRect.right,
      lineY + beamHeight / 2,
    );

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withOpacity(0.0),
          primaryColor.withOpacity(0.4),
          primaryColor.withOpacity(0.0),
        ],
      ).createShader(beamRect);

    canvas.drawRect(beamRect, beamPaint);

    // Sharp white core laser line
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);

    canvas.drawLine(
      Offset(ovalRect.left, lineY),
      Offset(ovalRect.right, lineY),
      linePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) {
    return oldDelegate.scanValue != scanValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color primaryColor;

  _ProgressRingPainter({
    required this.progress,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final ovalWidth = size.width * 0.65 + 16;
    final ovalHeight = size.height * 0.74 + 16;
    final ringRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    canvas.drawOval(ringRect, trackPaint);

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [
          primaryColor,
          Colors.cyanAccent,
          primaryColor,
        ],
      ).createShader(ringRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * math.min(progress, 1.0);
    canvas.drawArc(ringRect, -math.pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor;
  }
}