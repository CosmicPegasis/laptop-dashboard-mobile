import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:laptop_dashboard_mobile/services/api_service.dart';
import 'dart:io';

void main() {
  late Directory tempDir;
  late String testFilePath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('api_service_test_');
    final testFile = File('${tempDir.path}/test.txt');
    await testFile.writeAsString('test content');
    testFilePath = testFile.path;
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  group('ApiService', () {
    group('fetchStats', () {
      test('returns AppStats on successful response', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            '{"cpu_usage": 50.0, "ram_usage": 60.0, "cpu_temp": 70.0, "battery_percent": 80.0, "is_plugged": true}',
            200,
          );
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        final stats = await service.fetchStats();

        expect(stats.cpu, 50.0);
        expect(stats.ram, 60.0);
        expect(stats.temp, 70.0);
        expect(stats.battery, 80.0);
        expect(stats.isPlugged, true);
      });

      test('throws exception on non-200 status code', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Server error', 500);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(() => service.fetchStats(), throwsA(isA<Exception>()));
      });

      test('throws exception on invalid JSON payload (non-map)', () async {
        final mockClient = MockClient((request) async {
          return http.Response('[1, 2, 3]', 200);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(
          () => service.fetchStats(),
          throwsA(
            predicate((e) => e.toString().contains('Invalid stats payload')),
          ),
        );
      });
    });

    group('sleepLaptop', () {
      test('completes successfully on 200 response', () async {
        final mockClient = MockClient((request) async {
          return http.Response('', 200);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        await expectLater(service.sleepLaptop(), completes);
      });

      test('throws exception on non-200 status code', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Failed', 400);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(
          () => service.sleepLaptop(),
          throwsA(
            predicate((e) => e.toString().contains('Could not sleep laptop')),
          ),
        );
      });
    });

    group('uploadFile', () {
      test('completes successfully on 200 response', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          Response(statusCode: 200, requestOptions: RequestOptions(path: '')),
        );

        double progressValue = 0.0;
        await service.uploadFile(
          filePath: testFilePath,
          fileName: 'test.txt',
          onProgress: (progress) => progressValue = progress,
        );

        expect(progressValue, greaterThanOrEqualTo(0.0));
      });

      test('throws exception on DioException connectionTimeout', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(
            predicate((e) => e.toString().contains('Connection timeout')),
          ),
        );
      });

      test('throws exception on DioException sendTimeout', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.sendTimeout,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('Upload timed out'))),
        );
      });

      test('throws exception on DioException receiveTimeout', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.receiveTimeout,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(
            predicate((e) => e.toString().contains('Server response timeout')),
          ),
        );
      });

      test('throws exception on DioException badResponse', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 500,
              requestOptions: RequestOptions(path: ''),
            ),
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('Server error'))),
        );
      });

      test('throws exception on DioException connectionError', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.connectionError,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('Connection error'))),
        );
      });

      test('throws exception on DioException cancel', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubPost(
          'http://192.168.1.100:8081/upload',
          null,
          error: DioException(
            type: DioExceptionType.cancel,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.uploadFile(
            filePath: testFilePath,
            fileName: 'test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('cancelled'))),
        );
      });
    });

    group('forwardNotification', () {
      test('completes successfully on 200 response', () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, '/phone-notification');
          expect(request.headers['Content-Type'], 'application/json');
          return http.Response('', 200);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        await service.forwardNotification({'title': 'Test', 'body': 'Body'});
      });

      test('throws exception on non-200 status code', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Failed', 400);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(
          () => service.forwardNotification({'title': 'Test'}),
          throwsA(
            predicate((e) => e.toString().contains('Reverse sync failed')),
          ),
        );
      });
    });

    group('listFiles', () {
      test('returns list of FileInfo on successful response', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            '[{"name": "file1.txt", "size": 1024, "mod_time": 1609459200.0}, {"name": "file2.txt", "size": 2048, "mod_time": 1609545600.0}]',
            200,
          );
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        final files = await service.listFiles();

        expect(files.length, 2);
        expect(files[0].name, 'file1.txt');
        expect(files[0].size, 1024);
        expect(files[1].name, 'file2.txt');
        expect(files[1].size, 2048);
      });

      test('throws exception on non-200 status code', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Server error', 500);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(() => service.listFiles(), throwsA(isA<Exception>()));
      });

      test('throws exception on invalid payload (non-array)', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"error": "not a list"}', 200);
        });

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
        );

        expect(
          () => service.listFiles(),
          throwsA(
            predicate(
              (e) => e.toString().contains('Invalid file list payload'),
            ),
          ),
        );
      });
    });

    group('downloadFile', () {
      test('completes successfully', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          Response(statusCode: 200, requestOptions: RequestOptions(path: '')),
        );

        double progressValue = 0.0;
        await service.downloadFile(
          filename: 'test.txt',
          savePath: '/tmp/test.txt',
          onProgress: (progress) => progressValue = progress,
        );

        expect(progressValue, greaterThanOrEqualTo(0.0));
      });

      test('throws exception on DioException connectionTimeout', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          null,
          error: DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.downloadFile(
            filename: 'test.txt',
            savePath: '/tmp/test.txt',
            onProgress: (_) {},
          ),
          throwsA(
            predicate((e) => e.toString().contains('Connection timeout')),
          ),
        );
      });

      test('throws exception on DioException receiveTimeout', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          null,
          error: DioException(
            type: DioExceptionType.receiveTimeout,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.downloadFile(
            filename: 'test.txt',
            savePath: '/tmp/test.txt',
            onProgress: (_) {},
          ),
          throwsA(
            predicate((e) => e.toString().contains('Download timed out')),
          ),
        );
      });

      test('throws exception on DioException badResponse', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          null,
          error: DioException(
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 404,
              requestOptions: RequestOptions(path: ''),
            ),
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.downloadFile(
            filename: 'test.txt',
            savePath: '/tmp/test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('Server error'))),
        );
      });

      test('throws exception on DioException connectionError', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          null,
          error: DioException(
            type: DioExceptionType.connectionError,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.downloadFile(
            filename: 'test.txt',
            savePath: '/tmp/test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('Connection error'))),
        );
      });

      test('throws exception on DioException cancel', () async {
        final mockClient = MockClient(
          (request) async => http.Response('', 200),
        );
        final mockDio = _MockDio();

        final service = ApiService(
          laptopIp: '192.168.1.100',
          httpClient: mockClient,
          dio: mockDio,
        );

        mockDio.stubDownload(
          'http://192.168.1.100:8081/download/test.txt',
          null,
          error: DioException(
            type: DioExceptionType.cancel,
            requestOptions: RequestOptions(path: ''),
          ),
        );

        expect(
          () => service.downloadFile(
            filename: 'test.txt',
            savePath: '/tmp/test.txt',
            onProgress: (_) {},
          ),
          throwsA(predicate((e) => e.toString().contains('cancelled'))),
        );
      });
    });
  });
}

class _MockDio implements Dio {
  final Map<String, Response<dynamic>?> _postResponses = {};
  final Map<String, Response<dynamic>?> _downloadResponses = {};
  final Map<String, DioException?> _postErrors = {};
  final Map<String, DioException?> _downloadErrors = {};

  void stubPost(
    String url,
    Response<dynamic>? response, {
    DioException? error,
  }) {
    _postResponses[url] = response;
    _postErrors[url] = error;
  }

  void stubDownload(
    String url,
    Response<dynamic>? response, {
    DioException? error,
  }) {
    _downloadResponses[url] = response;
    _downloadErrors[url] = error;
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final error = _postErrors[path];
    if (error != null) {
      throw error;
    }
    return _postResponses[path] as Response<T>? ??
        Response<T>(
          statusCode: 200,
          requestOptions: RequestOptions(path: path),
        );
  }

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    void Function(int, int)? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String? lengthHeader = Headers.contentLengthHeader,
    Options? options,
    Object? data,
    FileAccessMode? fileAccessMode,
  }) async {
    final error = _downloadErrors[urlPath];
    if (error != null) {
      throw error;
    }
    return _downloadResponses[urlPath] ??
        Response(
          statusCode: 200,
          requestOptions: RequestOptions(path: urlPath),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
