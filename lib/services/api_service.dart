import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../models/app_stats.dart';

class ApiService {
  final String laptopIp;
  final Dio _dio = Dio();

  ApiService({required this.laptopIp});

  Future<AppStats> fetchStats() async {
    final response = await http
        .get(Uri.parse('http://$laptopIp:8081/stats'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid stats payload: expected JSON object');
      }
      return AppStats.fromJson(decoded);
    } else {
      throw Exception('Server returned ${response.statusCode}');
    }
  }

  Future<void> sleepLaptop() async {
    final response = await http
        .post(Uri.parse('http://$laptopIp:8081/sleep'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Could not sleep laptop (HTTP ${response.statusCode})');
    }
  }

  Future<void> uploadFile({
    required String filePath,
    required String fileName,
    required Function(double) onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final response = await _dio.post(
      'http://$laptopIp:8081/upload',
      data: formData,
      onSendProgress: (sent, total) {
        if (total <= 0) return;
        onProgress(sent / total);
      },
      options: Options(
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Upload failed (HTTP ${response.statusCode})');
    }
  }

  Future<void> forwardNotification(Map<String, dynamic> payload) async {
    final response = await http
        .post(
          Uri.parse('http://$laptopIp:8081/phone-notification'),
          headers: const {'Content-Type': 'application/json'},
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: 3));

    if (response.statusCode != 200) {
      throw Exception('Reverse sync failed (HTTP ${response.statusCode})');
    }
  }
}
