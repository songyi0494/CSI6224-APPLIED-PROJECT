import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/app_repository.dart';
import '../models/clinical_input.dart';
import '../models/pathway_evaluation.dart';

class ClinicalApiClient {
  ClinicalApiClient(this.url);
  final Uri url;
  Future<PathwayEvaluation> evaluate(ClinicalInput input) async {
    final client = http.Client();
    try {
      final response = await client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'facts': input.toFacts()}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200)
        throw const AppException(
          'We could not evaluate this assessment. Please try again.',
        );
      return PathwayEvaluation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const AppException(
        'The assessment service is unavailable. Please try again.',
      );
    } finally {
      client.close();
    }
  }
}
