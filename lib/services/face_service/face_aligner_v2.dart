import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// FaceAlignerV2 handles 5-point facial landmark alignment and tight
/// forehead/hair trimming to eliminate hair texture and background from
/// face recognition vectors.
class FaceAlignerV2 {
  FaceAlignerV2._();

  /// Crops the face tightly, stripping out forehead hair and background.
  static Future<img.Image?> cropFaceTight(
    File imageFile,
    Face face, {
    double foreheadTrimRatio = 0.18,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Bake EXIF orientation so image dimensions match MLKit boundingBox space
      image = img.bakeOrientation(image);

      // 1. Landmark-guided 2-Eye Alignment (Rotate image so eyes sit horizontally)
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (leftEye != null && rightEye != null) {
        final dx = rightEye.position.x - leftEye.position.x;
        final dy = rightEye.position.y - leftEye.position.y;
        final angleRad = atan2(dy, dx);
        final angleDeg = angleRad * 180 / pi;

        if (angleDeg.abs() > 2 && angleDeg.abs() < 45) {
          image = img.copyRotate(image, angle: angleDeg);
        }
      }

      final rect = face.boundingBox;

      // 2. Tight Hair Trimming:
      // Shift top boundary downwards by foreheadTrimRatio (e.g. 18%) to ignore upper hair/forehead.
      final topOffset = (rect.height * foreheadTrimRatio).toInt();

      int left = max(0, rect.left.toInt());
      int top = max(0, rect.top.toInt() + topOffset);
      int right = min(image.width, rect.right.toInt());
      int bottom = min(image.height, rect.bottom.toInt());

      int width = right - left;
      int height = bottom - top;

      if (width <= 0 || height <= 0) {
        return null;
      }

      final cropped = img.copyCrop(
        image,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      return cropped;
    } catch (e) {
      debugPrint("[FaceAlignerV2] Crop Error: $e");
      return null;
    }
  }

  /// Resizes cropped face image to target model input size (default 160x160 for 512-d FaceNet/ArcFace)
  static img.Image resizeToTarget(img.Image image, {int targetSize = 160}) {
    return img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Complete Face Alignment Pipeline V2
  static Future<img.Image?> alignFaceV2(
    File imageFile,
    Face face, {
    int targetSize = 160,
  }) async {
    final cropped = await cropFaceTight(imageFile, face);
    if (cropped == null) return null;
    return resizeToTarget(cropped, targetSize: targetSize);
  }
}
