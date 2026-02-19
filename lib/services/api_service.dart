import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../models/app_stats.dart';
import '../models/file_info.dart';

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

    try {
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
    } on DioException catch (e) {
      final message = switch (e.type) {
        DioExceptionType.connectionTimeout =>
          'Connection timeout - check if laptop is reachable',
        DioExceptionType.sendTimeout =>
          'Upload timed out - file may be too large',
        DioExceptionType.receiveTimeout => 'Server response timeout',
        DioExceptionType.badResponse =>
          'Server error (HTTP ${e.response?.statusCode ?? 'unknown'})',
        DioExceptionType.connectionError =>
          'Connection error - check IP address and network',
        DioExceptionType.cancel => 'Upload was cancelled',
        _ => 'Upload failed: ${e.message ?? 'unknown error'}',
      };
      throw Exception(message);
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

  Future<List<FileInfo>> listFiles() async {
    final response = await http
        .get(Uri.parse('http://$laptopIp:8081/list-files'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! List) {
        throw Exception('Invalid file list payload: expected JSON array');
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => FileInfo.fromJson(item))
          .toList();
    } else {
      throw Exception('Server returned ${response.statusCode}');
    }
  }

  Future<void> downloadFile({
    required String filename,
    required String savePath,
    required Function(double) onProgress,
  }) async {
    try {
      await _dio.download(
        'http://$laptopIp:8081/download/$filename',
        savePath,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress(received / total);
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
    } on DioException catch (e) {
      final message = switch (e.type) {
        DioExceptionType.connectionTimeout =>
          'Connection timeout - check if laptop is reachable',
        DioExceptionType.receiveTimeout =>
          'Download timed out - file may be too large',
        DioExceptionType.badResponse =>
          'Server error (HTTP ${e.response?.statusCode ?? 'unknown'})',
        DioExceptionType.connectionError =>
          'Connection error - check IP address and network',
        DioExceptionType.cancel => 'Download was cancelled',
        _ => 'Download failed: ${e.message ?? 'unknown error'}',
      };
      throw Exception(message);
    }
  }
}
