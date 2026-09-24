import 'dart:math';
import 'package:flutter/foundation.dart';

class FaceVerificationResultV2 {
  final bool matched;
  final double similarity;
  final double distance;
  final int matchedTemplateIndex;

  const FaceVerificationResultV2({
    required this.matched,
    required this.similarity,
    required this.distance,
    this.matchedTemplateIndex = 0,
  });
}

/// FaceMatcherV2 provides verification and comparison methods optimized
/// for 512-dimensional L2-normalized face embedding vectors.
class FaceMatcherV2 {
  FaceMatcherV2._();

  /// Recommended Cosine Similarity threshold for 512-d ArcFace/FaceNet embeddings (0.65 - 0.72)
  static const double defaultSimilarityThreshold = 0.65;

  /// Cosine Similarity computation
  static double cosineSimilarity(
    List<double> vector1,
    List<double> vector2,
  ) {
    if (vector1.length != vector2.length) {
      if (kDebugMode) {
        print("[FaceMatcherV2] ⚠️ Vector size mismatch (${vector1.length} vs ${vector2.length}). User needs to re-register face.");
      }
      return 0.0;
    }

    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < vector1.length; i++) {
      dot += vector1[i] * vector2[i];
      normA += vector1[i] * vector1[i];
      normB += vector2[i] * vector2[i];
    }

    if (normA == 0 || normB == 0) {
      return 0;
    }

    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Euclidean Distance computation
  static double euclideanDistance(
    List<double> vector1,
    List<double> vector2,
  ) {
    if (vector1.length != vector2.length) {
      return 99.0;
    }

    double sum = 0;
    for (int i = 0; i < vector1.length; i++) {
      final diff = vector1[i] - vector2[i];
      sum += diff * diff;
    }

    return sqrt(sum);
  }

  /// Verify a single live embedding against a single stored embedding vector
  static FaceVerificationResultV2 verifyFace({
    required List<double> liveEmbedding,
    required List<double> storedEmbedding,
    double threshold = defaultSimilarityThreshold,
  }) {
    final similarity = cosineSimilarity(
      liveEmbedding,
      storedEmbedding,
    );

    final distance = euclideanDistance(
      liveEmbedding,
      storedEmbedding,
    );

    return FaceVerificationResultV2(
      matched: similarity >= threshold,
      similarity: similarity,
      distance: distance,
      matchedTemplateIndex: 0,
    );
  }

  /// Verify a live embedding against multiple stored reference templates (Multi-Shot Enrollment)
  static FaceVerificationResultV2 verifyFaceMultiTemplates({
    required List<double> liveEmbedding,
    required List<List<double>> storedTemplates,
    double threshold = defaultSimilarityThreshold,
  }) {
    if (storedTemplates.isEmpty) {
      return const FaceVerificationResultV2(
        matched: false,
        similarity: 0.0,
        distance: 99.0,
      );
    }

    double maxSim = -1.0;
    double minDist = 999.0;
    int bestIndex = 0;

    for (int i = 0; i < storedTemplates.length; i++) {
      final sim = cosineSimilarity(liveEmbedding, storedTemplates[i]);
      final dist = euclideanDistance(liveEmbedding, storedTemplates[i]);

      if (sim > maxSim) {
        maxSim = sim;
        minDist = dist;
        bestIndex = i;
      }
    }

    return FaceVerificationResultV2(
      matched: maxSim >= threshold,
      similarity: maxSim,
      distance: minDist,
      matchedTemplateIndex: bestIndex,
    );
  }
}
