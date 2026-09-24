import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

enum FaceDetectionStatus {
  success,
  noFace,
  multipleFaces,
  error,
}

class FaceDetectionResult {
  final FaceDetectionStatus status;
  final Face? face;
  final File? normalizedImageFile;
  final String? message;

  const FaceDetectionResult({
    required this.status,
    this.face,
    this.normalizedImageFile,
    this.message,
  });
}

class MultiFaceDetectionResult {
  final List<Face> faces;
  final File normalizedImageFile;
  final Size imageSize;
  final String? error;

  const MultiFaceDetectionResult({
    required this.faces,
    required this.normalizedImageFile,
    this.imageSize = Size.zero,
    this.error,
  });
}

class NormalizedImage {
  final File file;
  final Size size;

  const NormalizedImage(this.file, this.size);
}

class FaceDetectorService {
  FaceDetectorService._();

  static final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: false,
      enableContours: false,
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: 0.15,
    ),
  );

  /// Detects face directly from an InputImage (e.g. from camera stream)
  static Future<FaceDetectionResult> detectFaceFromInputImage(InputImage inputImage) async {
    try {
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        return const FaceDetectionResult(
          status: FaceDetectionStatus.noFace,
          message: "No face detected.",
        );
      }

     /* if (faces.length > 1) {
        return const FaceDetectionResult(
          status: FaceDetectionStatus.multipleFaces,
          message: "Multiple faces detected.",
        );
      }*/

      return FaceDetectionResult(
        status: FaceDetectionStatus.success,
        face: faces.first,
      );
    } catch (e) {
      return FaceDetectionResult(
        status: FaceDetectionStatus.error,
        message: e.toString(),
      );
    }
  }

  /// Physically bakes EXIF rotation so image pixels are upright before MLKit detection
  static Future<NormalizedImage> normalizeOrientationWithSize(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return NormalizedImage(imageFile, Size.zero);

      final baked = img.bakeOrientation(decoded);
      final normalizedBytes = img.encodeJpg(baked, quality: 95);

      final normalizedPath = "${imageFile.path}_upright.jpg";
      final normalizedFile = File(normalizedPath);
      await normalizedFile.writeAsBytes(normalizedBytes);
      return NormalizedImage(
        normalizedFile,
        Size(baked.width.toDouble(), baked.height.toDouble()),
      );
    } catch (e) {
      debugPrint("Error baking orientation before face detection: $e");
      return NormalizedImage(imageFile, Size.zero);
    }
  }

  /// Physically bakes EXIF rotation so image pixels are upright before MLKit detection
  static Future<File> normalizeOrientation(File imageFile) async {
    final result = await normalizeOrientationWithSize(imageFile);
    return result.file;
  }

  /// Detects exactly one face after baking rotation into image file.
  static Future<FaceDetectionResult> detectFace(File imageFile) async {
    try {
      final normalized = await normalizeOrientationWithSize(imageFile);
      final inputImage = InputImage.fromFile(normalized.file);

      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        return FaceDetectionResult(
          status: FaceDetectionStatus.noFace,
          normalizedImageFile: normalized.file,
          message: "No face detected.",
        );
      }

      if (faces.length > 1) {
        return FaceDetectionResult(
          status: FaceDetectionStatus.multipleFaces,
          normalizedImageFile: normalized.file,
          message: "Multiple faces detected.",
        );
      }

      return FaceDetectionResult(
        status: FaceDetectionStatus.success,
        face: faces.first,
        normalizedImageFile: normalized.file,
      );
    } catch (e) {
      debugPrint("Face Detection Error : $e");

      return FaceDetectionResult(
        status: FaceDetectionStatus.error,
        message: e.toString(),
      );
    }
  }

  /// Detects all faces present in the image for multi-face detection and matching
  static Future<MultiFaceDetectionResult> detectAllFaces(File imageFile) async {
    try {
      final normalized = await normalizeOrientationWithSize(imageFile);
      final inputImage = InputImage.fromFile(normalized.file);
      final faces = await _detector.processImage(inputImage);
      return MultiFaceDetectionResult(
        faces: faces,
        normalizedImageFile: normalized.file,
        imageSize: normalized.size,
      );
    } catch (e) {
      debugPrint("Multi-Face Detection Error : $e");
      return MultiFaceDetectionResult(
        faces: const [],
        normalizedImageFile: imageFile,
        imageSize: Size.zero,
        error: e.toString(),
      );
    }
  }

  /// Quick helper
  static Future<bool> hasSingleFace(File imageFile) async {
    final result = await detectFace(imageFile);
    return result.status == FaceDetectionStatus.success;
  }

  /// Optional quality validation
  static String? validateFace(Face face) {
    final rect = face.boundingBox;

    if (rect.width < 50 || rect.height < 50) {
      return "Face is too far away. Please move closer.";
    }

    final headY = face.headEulerAngleY ?? 0;
    final headX = face.headEulerAngleX ?? 0;

    if (headY.abs() > 35) {
      return "Please turn your head straight to the camera.";
    }

    if (headX.abs() > 35) {
      return "Please look straight at the camera.";
    }

    return null;
  }

  static bool isFaceValid(Face face) {
    return validateFace(face) == null;
  }

  static Future<void> dispose() async {
    await _detector.close();
  }
}