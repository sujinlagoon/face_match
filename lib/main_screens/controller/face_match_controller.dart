import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../data/url.dart';
import '../../services/face_service/face_matcher_v2.dart';
import '../model/profile_face_model.dart';

class FaceMatchMatchResult {
  final EmployeeModel employee;
  final double similarity;

  const FaceMatchMatchResult({
    required this.employee,
    required this.similarity,
  });
}

class FaceMatchController extends GetxController {
  bool isFaceMatch = false;
  String? errorMessage;
  List<EmployeeModel> employeeList = [];

  /// Fetches registered employee face profiles for a given TimeKeeper ID
  Future<bool> faceMatchApi({String? timeKeeperId}) async {
    isFaceMatch = true;
    errorMessage = null;
    update();

    try {
      final uri = Uri.parse('${Url.faceMatch}?EmployeeNo=${timeKeeperId ?? ''}');
      if (kDebugMode) {
        print("[FaceMatchController] Fetching face profiles from: $uri");
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        print("[FaceMatchController] Status: ${response.statusCode}");
      }

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);

        List<dynamic> rawList = [];
        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          if (decoded['data'] is List) {
            rawList = decoded['data'];
          } else if (decoded['result'] is List) {
            rawList = decoded['result'];
          } else if (decoded['EmployeeList'] is List) {
            rawList = decoded['EmployeeList'];
          }
        }

        final parsedList = rawList
            .map((item) => EmployeeModel.fromJson(item as Map<String, dynamic>))
            .toList();

        // Keep employees who have valid face embeddings
        employeeList = parsedList
            .where((emp) => emp.faceEmbedding != null && emp.faceEmbedding!.isNotEmpty)
            .toList();

        if (kDebugMode) {
          print(
            "[FaceMatchController] Loaded ${employeeList.length} employees with embeddings (total received: ${parsedList.length})",
          );
        }
        return true;
      } else {
        errorMessage = "Server returned status ${response.statusCode}";
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print("[FaceMatchController] Error fetching face profiles: $e");
      }
      errorMessage = e.toString();
      return false;
    } finally {
      isFaceMatch = false;
      update();
    }
  }

  /// 1:N Embedding search: Compares a live face embedding against all loaded employees.
  /// Returns the employee with the highest similarity score if above threshold.
  FaceMatchMatchResult? matchLiveEmbedding(
    List<double> liveEmbedding, {
    double threshold = FaceMatcherV2.defaultSimilarityThreshold,
  }) {
    if (employeeList.isEmpty || liveEmbedding.isEmpty) {
      return null;
    }

    EmployeeModel? bestEmployee;
    double highestSimilarity = -1.0;

    for (final employee in employeeList) {
      final storedEmbedding = employee.faceEmbedding;
      if (storedEmbedding == null || storedEmbedding.isEmpty) continue;

      final similarity = FaceMatcherV2.cosineSimilarity(
        liveEmbedding,
        storedEmbedding,
      );

      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        bestEmployee = employee;
      }
    }

    if (bestEmployee != null && highestSimilarity >= threshold) {
      return FaceMatchMatchResult(
        employee: bestEmployee,
        similarity: highestSimilarity,
      );
    }

    return null;
  }
}
