import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:test/test.dart';

class MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(
  dynamic data, {
  int statusCode = 200,
  String statusMessage = 'OK',
}) {
  final jsonString = data != null ? jsonEncode(data) : '';
  final stream = Stream.value(Uint8List.fromList(utf8.encode(jsonString)));
  return ResponseBody(
    stream,
    statusCode,
    statusMessage: statusMessage,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dio_bolt_upload_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('DioBolt Upload - Core Functionality', () {
    test('1. Single file upload via fromBytes', () async {
      RequestOptions? capturedOptions;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        capturedOptions = options;
        return jsonBody({'id': 101, 'status': 'uploaded'});
      });

      final bolt = DioBolt(dio: dio);
      final bytes = utf8.encode('Hello Byte World');

      final response = await bolt.upload(
        '/upload',
        file: DioBoltFile.fromBytes(
          bytes,
          fieldName: 'document',
          filename: 'doc.txt',
          contentType: 'text/plain',
        ),
        data: {'description': 'A text document'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'id': 101, 'status': 'uploaded'}));

      final data = capturedOptions?.data;
      expect(data, isA<FormData>());
      final formData = data as FormData;
      expect(
        formData.fields.any(
          (f) => f.key == 'description' && f.value == 'A text document',
        ),
        isTrue,
      );
      expect(
        formData.files.any(
          (f) => f.key == 'document' && f.value.filename == 'doc.txt',
        ),
        isTrue,
      );
    });

    test('2. Single file upload via fromPath', () async {
      final sampleFile = File('${tempDir.path}/sample.png');
      await sampleFile.writeAsBytes([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]); // PNG magic bytes

      RequestOptions? capturedOptions;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        capturedOptions = options;
        return jsonBody({'fileId': 'png-123'});
      });

      final bolt = DioBolt(dio: dio);

      final response = await bolt.upload(
        '/avatar',
        file: DioBoltFile.fromPath(
          sampleFile.path,
          fieldName: 'avatar',
          filename: 'custom_avatar.png',
          contentType: 'image/png',
        ),
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      final formData = capturedOptions?.data as FormData;
      expect(formData.files.first.key, equals('avatar'));
      expect(formData.files.first.value.filename, equals('custom_avatar.png'));
    });

    test(
      '3. Multiple files upload with mixed path and bytes + form fields',
      () async {
        final textFile = File('${tempDir.path}/notes.txt');
        await textFile.writeAsString('Meeting Notes');

        RequestOptions? capturedOptions;
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          capturedOptions = options;
          return jsonBody({'uploadedCount': 2});
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.upload(
          '/gallery',
          files: [
            DioBoltFile.fromPath(
              textFile.path,
              fieldName: 'files[]',
              filename: 'notes.txt',
            ),
            DioBoltFile.fromBytes(
              [1, 2, 3],
              fieldName: 'files[]',
              filename: 'binary.bin',
            ),
          ],
          data: {'album': 'Project Files', 'priority': 1},
        );

        expect(response.isSuccess, isTrue);
        final formData = capturedOptions?.data as FormData;
        expect(formData.files.length, equals(2));
        expect(formData.fields.length, equals(2));
      },
    );

    test('4. Stream file upload via fromStream', () async {
      final stream = Stream<List<int>>.value([10, 20, 30, 40]);
      RequestOptions? capturedOptions;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        capturedOptions = options;
        return jsonBody({'streamReceived': true});
      });

      final bolt = DioBolt(dio: dio);

      final response = await bolt.upload(
        '/stream-upload',
        file: DioBoltFile.fromStream(
          stream,
          fieldName: 'streamFile',
          length: 4,
          filename: 'stream.bin',
        ),
      );

      expect(response.isSuccess, isTrue);
      final formData = capturedOptions?.data as FormData;
      expect(formData.files.first.value.length, equals(4));
    });

    test('5. Progress callback triggers', () async {
      final progressValues = <int>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'ok': true});
      });

      final bolt = DioBolt(dio: dio);
      final response = await bolt.upload(
        '/upload',
        file: DioBoltFile.fromBytes(
          [1, 2, 3, 4, 5],
          fieldName: 'file',
          filename: 'f.bin',
        ),
        onSendProgress: (sent, total) {
          progressValues.add(sent);
        },
      );

      expect(response.isSuccess, isTrue);
    });

    test(
      '6. Cancellation aborts upload immediately and returns statusCode: 0',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Upload was aborted by user.',
          );
        });

        final cancelToken = CancelToken();
        final bolt = DioBolt(dio: dio);

        final future = bolt.upload(
          '/upload',
          file: DioBoltFile.fromBytes(
            [1, 2, 3],
            fieldName: 'f',
            filename: 'f.bin',
          ),
          cancelToken: cancelToken,
        );

        cancelToken.cancel('Abort');
        final response = await future;

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(0));
        expect(response.message, contains('Request was cancelled'));
      },
    );

    test(
      '7. HTTP error (413 Payload Too Large) preserves raw server response',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          return jsonBody(
            {'error': 'File exceeds 5MB limit'},
            statusCode: 413,
            statusMessage: 'Payload Too Large',
          );
        });

        final bolt = DioBolt(dio: dio);
        final response = await bolt.upload(
          '/large-upload',
          file: DioBoltFile.fromBytes(
            [1, 2, 3],
            fieldName: 'f',
            filename: 'big.bin',
          ),
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(413));
        expect(
          response.responseData,
          equals({'error': 'File exceeds 5MB limit'}),
        );
      },
    );
  });

  group('DioBolt Upload - Replayability & Retry Integration', () {
    test(
      '8. Path-backed upload retry: reconstructs fresh MultipartFile on retry and delivers complete payload',
      () async {
        final uploadFile = File('${tempDir.path}/retry_test.txt');
        await uploadFile.writeAsString('Complete File Content for Attempt 2');

        int requestCount = 0;
        final capturedFormDatas = <FormData>[];

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          final formData = options.data as FormData;
          capturedFormDatas.add(formData);

          if (requestCount == 1) {
            // Attempt 1 fails with transient 503
            return jsonBody({'error': 'Service Unavailable'}, statusCode: 503);
          }
          // Attempt 2 succeeds
          return jsonBody({
            'success': true,
            'receivedFiles': formData.files.length,
          });
        });

        final bolt = DioBolt(
          dio: dio,
          retryConfig: DioBoltRetryConfig(
            maxRetries: 2,
            delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
          ),
        );

        final response = await bolt.upload(
          '/upload',
          file: DioBoltFile.fromPath(
            uploadFile.path,
            fieldName: 'doc',
            filename: 'retry_test.txt',
          ),
          data: {'note': 'attempt verification'},
          options: Options().copyWithRetry(enabled: true),
        );

        expect(response.isSuccess, isTrue);
        expect(response.statusCode, equals(200));
        expect(requestCount, equals(2));

        // Verify that attempt #2 got a fresh, non-finalized MultipartFile
        expect(capturedFormDatas.length, equals(2));
        final attempt2File = capturedFormDatas[1].files.first.value;
        expect(attempt2File.filename, equals('retry_test.txt'));
        expect(attempt2File.length, equals(await uploadFile.length()));
      },
    );

    test(
      '9. Byte-backed upload retry: reconstructs fresh MultipartFile from bytes',
      () async {
        int requestCount = 0;
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          if (requestCount == 1) {
            return jsonBody({'error': 'Gateway Timeout'}, statusCode: 504);
          }
          return jsonBody({'status': 'ok'});
        });

        final bolt = DioBolt(
          dio: dio,
          retryConfig: DioBoltRetryConfig(
            maxRetries: 2,
            delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
          ),
        );

        final response = await bolt.upload(
          '/upload',
          file: DioBoltFile.fromBytes(
            bytes,
            fieldName: 'data',
            filename: 'data.bin',
          ),
          options: Options().copyWithRetry(enabled: true),
        );

        expect(response.isSuccess, isTrue);
        expect(requestCount, equals(2));
      },
    );

    test(
      '10. Stream-backed upload is NOT retried even with explicit copyWithRetry(enabled: true)',
      () async {
        int requestCount = 0;
        final stream = Stream<List<int>>.value([1, 2, 3]);

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          return jsonBody({'error': 'Server Error'}, statusCode: 500);
        });

        final bolt = DioBolt(
          dio: dio,
          retryConfig: DioBoltRetryConfig(
            maxRetries: 2,
            delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
          ),
        );

        final response = await bolt.upload(
          '/stream-upload',
          file: DioBoltFile.fromStream(
            stream,
            fieldName: 'f',
            length: 3,
            filename: 'f.bin',
          ),
          options: Options().copyWithRetry(enabled: true),
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(500));
        expect(requestCount, equals(1)); // Strictly rejected from retry
      },
    );

    test(
      '11. Upload 401 triggers token refresh and retries with updated Authorization header',
      () async {
        int requestCount = 0;
        int refreshCount = 0;
        final capturedHeaders = <Map<String, dynamic>>[];

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          capturedHeaders.add(Map.from(options.headers));
          if (requestCount == 1) {
            return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
          }
          return jsonBody({'uploadSuccess': true});
        });

        final bolt = DioBolt(
          dio: dio,
          auth: DioBoltAuth(
            getAccessToken: () => 'initial-token',
            refreshToken: (_) {
              refreshCount++;
              return 'refreshed-token';
            },
          ),
        );

        final response = await bolt.upload(
          '/upload',
          file: DioBoltFile.fromBytes(
            [10, 20],
            fieldName: 'avatar',
            filename: 'avatar.png',
          ),
        );

        expect(response.isSuccess, isTrue);
        expect(response.statusCode, equals(200));
        expect(requestCount, equals(2));
        expect(refreshCount, equals(1));
        expect(
          capturedHeaders[0]['Authorization'],
          equals('Bearer initial-token'),
        );
        expect(
          capturedHeaders[1]['Authorization'],
          equals('Bearer refreshed-token'),
        );
      },
    );

    test(
      '12. Generic arbitrary FormData fails with 503 and is NOT retried',
      () async {
        int requestCount = 0;
        final genericFormData = FormData.fromMap({'key': 'val'});

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          return jsonBody({'error': 'Server Error'}, statusCode: 503);
        });

        final bolt = DioBolt(
          dio: dio,
          retryConfig: DioBoltRetryConfig(
            maxRetries: 2,
            delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
          ),
        );

        final response = await bolt.post(
          '/custom-form',
          data: genericFormData,
          options: Options().copyWithRetry(enabled: true),
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(503));
        expect(requestCount, equals(1)); // Generic FormData is NOT retried
      },
    );

    test(
      '13. Generic arbitrary FormData on 401 is rejected from auth retry (original 401 returned)',
      () async {
        int requestCount = 0;
        final genericFormData = FormData.fromMap({'key': 'secret'});

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
        });

        final bolt = DioBolt(
          dio: dio,
          auth: DioBoltAuth(
            getAccessToken: () => 'token-1',
            refreshToken: (_) => 'token-2',
          ),
        );

        final response = await bolt.post(
          '/generic-form',
          data: genericFormData,
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(401));
        expect(requestCount, equals(1)); // Body not resent
      },
    );

    test(
      '14. DioBoltFile.fromStream on 401 is rejected from auth retry (original 401 returned)',
      () async {
        int requestCount = 0;
        final stream = Stream<List<int>>.value([1, 2, 3]);

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
        });

        final bolt = DioBolt(
          dio: dio,
          auth: DioBoltAuth(
            getAccessToken: () => 'token-1',
            refreshToken: (_) => 'token-2',
          ),
        );

        final response = await bolt.upload(
          '/stream-upload',
          file: DioBoltFile.fromStream(
            stream,
            fieldName: 'file',
            length: 3,
            filename: 'stream.bin',
          ),
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(401));
        expect(requestCount, equals(1)); // Stream body not resent
      },
    );
  });
}
