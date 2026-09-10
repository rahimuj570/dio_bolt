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

ResponseBody binaryBody(
  List<int> bytes, {
  int statusCode = 200,
  String statusMessage = 'OK',
}) {
  final stream = Stream.value(Uint8List.fromList(bytes));
  return ResponseBody(
    stream,
    statusCode,
    statusMessage: statusMessage,
    headers: {
      Headers.contentTypeHeader: ['application/octet-stream'],
      Headers.contentLengthHeader: [bytes.length.toString()],
    },
  );
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
    tempDir = await Directory.systemTemp.createTemp('dio_bolt_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DioBolt Download - Core Functionality', () {
    test(
      '1. File download saves content and returns savePath in responseData',
      () async {
        final savePath = '${tempDir.path}/report.pdf';
        final payload = utf8.encode('PDF Document Data %PDF-1.4');

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          return binaryBody(payload);
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.download(
          '/files/report.pdf',
          savePath: savePath,
        );

        expect(response.isSuccess, isTrue);
        expect(response.statusCode, equals(200));
        expect(response.responseData, equals(savePath));

        final savedFile = File(savePath);
        expect(await savedFile.exists(), isTrue);
        expect(await savedFile.readAsBytes(), equals(payload));
      },
    );

    test(
      '1b. Nonexistent nested parent directory is created automatically and temp cleaned',
      () async {
        final savePath = '${tempDir.path}/nested/deep/level/report.pdf';
        final payload = utf8.encode('Deep nested pdf content');

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          return binaryBody(payload);
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.download(
          '/files/report.pdf',
          savePath: savePath,
        );

        expect(response.isSuccess, isTrue);
        expect(response.statusCode, equals(200));
        expect(response.responseData, equals(savePath));

        final savedFile = File(savePath);
        expect(await savedFile.exists(), isTrue);
        expect(await savedFile.readAsBytes(), equals(payload));

        final parentDir = savedFile.parent;
        final parentFiles = await parentDir.list().toList();
        expect(parentFiles.where((f) => f.path.endsWith('.tmp')), isEmpty);
      },
    );

    test('2. downloadBytes returns in-memory Uint8List', () async {
      final payload = [1, 2, 3, 4, 5, 6, 7, 8];

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return binaryBody(payload);
      });

      final bolt = DioBolt(dio: dio);

      final response = await bolt.downloadBytes('/images/thumbnail.png');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, isA<Uint8List>());
      expect(response.responseData, equals(Uint8List.fromList(payload)));
    });

    test('3. Download onReceiveProgress callback tracks bytes', () async {
      final savePath = '${tempDir.path}/progress.bin';
      final payload = List.generate(100, (i) => i);
      final progressEvents = <int>[];

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return binaryBody(payload);
      });

      final bolt = DioBolt(dio: dio);

      final response = await bolt.download(
        '/file',
        savePath: savePath,
        onReceiveProgress: (received, total) {
          progressEvents.add(received);
        },
      );

      expect(response.isSuccess, isTrue);
      expect(progressEvents, isNotEmpty);
    });

    test(
      '4. Pre-flight overwrite: false returns conflict response without network request',
      () async {
        final existingFile = File('${tempDir.path}/existing.txt');
        await existingFile.writeAsString('Original Content');

        int requestCount = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          return binaryBody(utf8.encode('New Content'));
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.download(
          '/file.txt',
          savePath: existingFile.path,
          overwrite: false,
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(0));
        expect(response.message, contains('already exists'));
        expect(requestCount, equals(0)); // Proves zero network request sent!

        // Original file remains untouched
        expect(await existingFile.readAsString(), equals('Original Content'));
      },
    );

    test(
      '5. overwrite: true keeps existing destination intact until download completes successfully',
      () async {
        final existingFile = File('${tempDir.path}/will_replace.txt');
        await existingFile.writeAsString('Untouched Initial Content');

        final inFlightCompleter = Completer<void>();
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          // Verify while in-flight that the existing file is still untouched
          expect(
            existingFile.readAsStringSync(),
            equals('Untouched Initial Content'),
          );
          inFlightCompleter.complete();
          return binaryBody(utf8.encode('Brand New Content'));
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.download(
          '/file.txt',
          savePath: existingFile.path,
          overwrite: true,
        );

        await inFlightCompleter.future;
        expect(response.isSuccess, isTrue);
        expect(await existingFile.readAsString(), equals('Brand New Content'));
      },
    );

    test(
      '6. Failed download (404) cleans up temp file and does not touch destination',
      () async {
        final savePath = '${tempDir.path}/missing.pdf';

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          return jsonBody(
            {'error': 'Not Found'},
            statusCode: 404,
            statusMessage: 'Not Found',
          );
        });

        final bolt = DioBolt(dio: dio);

        final response = await bolt.download(
          '/not-found.pdf',
          savePath: savePath,
        );

        expect(response.isSuccess, isFalse);
        expect(response.statusCode, equals(404));
        expect(await File(savePath).exists(), isFalse);

        // Verify no dangling .tmp files remain in directory
        final dirFiles = await tempDir.list().toList();
        expect(dirFiles.where((f) => f.path.endsWith('.tmp')), isEmpty);
      },
    );

    test('7. Cancelled download cleans up temp file immediately', () async {
      final savePath = '${tempDir.path}/cancelled.bin';
      final cancelToken = CancelToken();

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: 'Download cancelled by user',
        );
      });

      final bolt = DioBolt(dio: dio);

      final future = bolt.download(
        '/large.bin',
        savePath: savePath,
        cancelToken: cancelToken,
      );

      cancelToken.cancel('User aborted');
      final response = await future;

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(await File(savePath).exists(), isFalse);

      final dirFiles = await tempDir.list().toList();
      expect(dirFiles.where((f) => f.path.endsWith('.tmp')), isEmpty);
    });
  });

  group('DioBolt Download - Auth & Retry Integration', () {
    test(
      '8. Download retry on 503 cleans temp file and succeeds on attempt #2',
      () async {
        final savePath = '${tempDir.path}/retry_download.pdf';
        int requestCount = 0;
        final payload = utf8.encode('Final Download Content');

        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        dio.httpClientAdapter = MockAdapter((options) async {
          requestCount++;
          if (requestCount == 1) {
            return jsonBody({'error': 'Service Unavailable'}, statusCode: 503);
          }
          return binaryBody(payload);
        });

        final bolt = DioBolt(
          dio: dio,
          retryConfig: DioBoltRetryConfig(
            maxRetries: 2,
            delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
          ),
        );

        final response = await bolt.download('/file', savePath: savePath);

        expect(response.isSuccess, isTrue);
        expect(requestCount, equals(2));
        expect(await File(savePath).exists(), isTrue);
        expect(await File(savePath).readAsBytes(), equals(payload));

        final dirFiles = await tempDir.list().toList();
        expect(dirFiles.where((f) => f.path.endsWith('.tmp')), isEmpty);
      },
    );

    test(
      '9. Download 401 triggers token refresh and completes download with new token',
      () async {
        final savePath = '${tempDir.path}/auth_download.pdf';
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
          return binaryBody(utf8.encode('Authenticated File'));
        });

        final bolt = DioBolt(
          dio: dio,
          auth: DioBoltAuth(
            getAccessToken: () => 'token-1',
            refreshToken: (_) {
              refreshCount++;
              return 'token-2';
            },
          ),
        );

        final response = await bolt.download(
          '/protected-file',
          savePath: savePath,
        );

        expect(response.isSuccess, isTrue);
        expect(response.statusCode, equals(200));
        expect(requestCount, equals(2));
        expect(refreshCount, equals(1));
        expect(capturedHeaders[0]['Authorization'], equals('Bearer token-1'));
        expect(capturedHeaders[1]['Authorization'], equals('Bearer token-2'));
        expect(
          await File(savePath).readAsString(),
          equals('Authenticated File'),
        );
      },
    );
  });
}
