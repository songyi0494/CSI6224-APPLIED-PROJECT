import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pathway_evaluation.dart';

class ClinicalApiClient {
  const ClinicalApiClient({
    required this.evaluatePathway1Url,
    required this.accessTokenProvider,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final Uri evaluatePathway1Url;
  final Future<String?> Function() accessTokenProvider;
  final http.Client? _httpClient;

  Future<PathwayEvaluation> evaluatePathway1(Map<String, Object?> facts) async {
    final client = _httpClient ?? http.Client();
    final token = await accessTokenProvider();
    final response = await client.post(
      evaluatePathway1Url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'facts': facts}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClinicalApiException(
        body['error']?.toString() ?? 'Pathway evaluation failed',
      );
    }

    return PathwayEvaluation.fromJson(body);
  }
}

class ClinicalApiException implements Exception {
  const ClinicalApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
