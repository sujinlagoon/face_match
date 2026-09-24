import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import '../../data/url.dart';
import 'face_aligner_v2.dart';
import 'face_embedding_v2.dart';
import 'face_matcher_v2.dart';

/// FaceServiceV2 provides the complete, upgraded 512-dimensional face recognition
/// pipeline featuring 5-point landmark alignment and tight hair trimming.
class FaceServiceV2 {
  FaceServiceV2._();

  /// Process input image file and face object to extract 512-d normalized embedding vector
  static Future<List<double>?> extractEmbeddingFromImage({
    required File imageFile,
    required Face face,
  }) async {
    try {
      final alignedImage = await FaceAlignerV2.alignFaceV2(imageFile, face);
      if (alignedImage == null) {
        if (kDebugMode) {
          print("[FaceServiceV2] ❌ Tight face alignment returned null.");
        }
        return null;
      }

      final embedding = await FaceEmbeddingServiceV2.getEmbedding(alignedImage);
      return embedding;
    } catch (e) {
      if (kDebugMode) {
        print("[FaceServiceV2] ❌ Error extracting V2 embedding: $e");
      }
      return null;
    }
  }

  /// Register face embedding for an employee/user
  static Future<bool> registerFace({
    required String employeeId,
    required List<double> faceEmbedding,
    String? realFace,
  }) async {
    try {
      if (kDebugMode) {
        print(
            "[FaceServiceV2] Registering face embedding for '$employeeId' (${faceEmbedding.length} values)");
      }

      final response = await http.post(
        Uri.parse(Url.faceRegister),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'EnrollmentID': employeeId,
          'FaceEmbedding': faceEmbedding,
          "RealFace": realFace,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (kDebugMode) {
          print(
              "[FaceServiceV2] ✅ Face registered successfully on server for $employeeId");
        }
        return true;
      } else {
        if (kDebugMode) {
          print(     "[FaceServiceV2] ⚠️ Face register server returned ${response.statusCode}: ${response.body}");
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print("[FaceServiceV2] ⚠️ Face register network notification: $e");
      }
      return true;
    }
  }

  /// Backward-compatible alias
  static Future<bool> registerFaceV2({
    required String userKey,
    required List<double> faceEmbedding,
    String? realFace,
  }) async {
    return registerFace(
      employeeId: userKey,
      faceEmbedding: faceEmbedding,
      realFace: realFace,
    );
  }

  /// Verify a live face embedding against stored V2 vector for a given userKey
  static Future<FaceVerificationResultV2> verifyLiveFaceV2({
    required File imageFile,
    required Face face,
    required List<double> storedEmbedding,
    double threshold = FaceMatcherV2.defaultSimilarityThreshold,
  }) async {
    final liveEmbedding = await extractEmbeddingFromImage(
      imageFile: imageFile,
      face: face,
    );

    if (liveEmbedding == null) {
      return const FaceVerificationResultV2(
        matched: false,
        similarity: 0.0,
        distance: 99.0,
      );
    }

    return FaceMatcherV2.verifyFace(
      liveEmbedding: liveEmbedding,
      storedEmbedding: storedEmbedding,
      threshold: threshold,
    );
  }
}
