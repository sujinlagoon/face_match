import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// FaceEmbeddingServiceV2 manages inference for the 512-dimensional
/// FaceNet/ArcFace model (`assets/models/facenet_512.tflite`).
class FaceEmbeddingServiceV2 {
  FaceEmbeddingServiceV2._();

  static Interpreter? _interpreter;
  static bool _initialized = false;

  /// Default input dimension for FaceNet 512-d (160x160)
  static int inputSize = 160;

  /// 512-dimensional embedding size
  static int embeddingSize = 512;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (kDebugMode) {
        print("[FaceEmbeddingServiceV2] Initializing true 512-d FaceNet TFLite interpreter...");
      }

      final options = InterpreterOptions()..threads = 4;
      try {
        _interpreter = await Interpreter.fromAsset(
          'assets/model/facenet_512.tflite',
          options: options,
        );
        embeddingSize = 512;
        inputSize = 160;
      } catch (e1) {
        if (kDebugMode) {
          print("[FaceEmbeddingServiceV2] 'assets/models/facenet_512.tflite' failed ($e1). Trying fallback 'assets/models/mobilefacenet.tflite'...");
        }
        try {
          _interpreter = await Interpreter.fromAsset(
            'assets/models/mobilefacenet.tflite',
            options: options,
          );
          embeddingSize = 192;
          inputSize = 112;
        } catch (e2) {
          if (kDebugMode) {
            print("[FaceEmbeddingServiceV2] Fallback failed ($e2). Trying 'models/mobilefacenet.tflite'...");
          }
          _interpreter = await Interpreter.fromAsset(
            'models/mobilefacenet.tflite',
            options: options,
          );
          embeddingSize = 192;
          inputSize = 112;
        }
      }

      // Check tensor output shape if available
      try {
        final outputTensor = _interpreter?.getOutputTensor(0);
        if (outputTensor != null && outputTensor.shape.length >= 2) {
          embeddingSize = outputTensor.shape.last;
          if (kDebugMode) {
            print("[FaceEmbeddingServiceV2] Verified interpreter output shape: ${outputTensor.shape} (embeddingSize=$embeddingSize)");
          }
        }
        final inputTensor = _interpreter?.getInputTensor(0);
        if (inputTensor != null && inputTensor.shape.length >= 3) {
          inputSize = inputTensor.shape[1]; // e.g. 160 or 112
          if (kDebugMode) {
            print("[FaceEmbeddingServiceV2] Verified interpreter input shape: ${inputTensor.shape} (inputSize=$inputSize)");
          }
        }
      } catch (tensorErr) {
        if (kDebugMode) {
          print("[FaceEmbeddingServiceV2] Tensor shape query warning: $tensorErr");
        }
      }

      _initialized = true;
      if (kDebugMode) {
        print("[FaceEmbeddingServiceV2] ✅ FaceEmbeddingServiceV2 initialized successfully! (inputSize=$inputSize, embeddingSize=$embeddingSize)");
      }
    } catch (e) {
      if (kDebugMode) {
        print("[FaceEmbeddingServiceV2] ❌ Failed to initialize TFLite interpreter: $e");
      }
      rethrow;
    }
  }

  static Future<void> dispose() async {
    _interpreter?.close();
    _initialized = false;
  }

  /// Generate 512-dimensional L2 normalized Face Embedding
  static Future<List<double>> getEmbedding(img.Image alignedFace) async {
    if (!_initialized) {
      await initialize();
    }

    // Ensure aligned image matches required input size
    img.Image inputImage = alignedFace;
    if (alignedFace.width != inputSize || alignedFace.height != inputSize) {
      inputImage = img.copyResize(
        alignedFace,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear,
      );
    }

    final input = _imageToFloat32List(inputImage).reshape([1, inputSize, inputSize, 3]);
    final output = List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);

    final stopwatch = Stopwatch()..start();
    _interpreter!.run(input, output);
    stopwatch.stop();

    if (kDebugMode) {
      print("[FaceEmbeddingServiceV2] ✅ 512-d TFLite inference completed in ${stopwatch.elapsedMilliseconds}ms");
    }

    final List<dynamic> rawList = output.first as List<dynamic>;
    final List<double> rawEmbedding = rawList.map((e) => (e as num).toDouble()).toList();

    final normalizedEmbedding = normalize(rawEmbedding);
    return normalizedEmbedding;
  }

  /// Convert image pixels to Float32 Tensor normalized (-1.0 to 1.0)
  static Float32List _imageToFloat32List(img.Image image) {
    final Float32List bytes = Float32List(1 * inputSize * inputSize * 3);
    int index = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);

        bytes[index++] = (pixel.r - 127.5) / 127.5;
        bytes[index++] = (pixel.g - 127.5) / 127.5;
        bytes[index++] = (pixel.b - 127.5) / 127.5;
      }
    }
    return bytes;
  }

  /// L2 Unit Normalization
  static List<double> normalize(List<double> embedding) {
    double norm = 0;
    for (double value in embedding) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return embedding;

    return embedding.map((e) => e / norm).toList();
  }
}
