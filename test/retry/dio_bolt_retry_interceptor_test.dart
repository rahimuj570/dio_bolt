import 'dart:async';
import 'dart:convert';
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
  group('DioBoltRetryInterceptor - Integration Tests', () {
    test('1. Transient 503 succeeds on retry 1', () async {
      int requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          return jsonBody({'error': 'Unavailable'}, statusCode: 503, statusMessage: 'Service Unavailable');
        }
        return jsonBody({'status': 'recovered'});
      });

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          maxRetries: 3,
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/service');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'status': 'recovered'}));
      expect(requestCount, equals(2)); // 1 initial + 1 retry
    });

    test('2. Multiple retries: 500 -> 500 -> 200', () async {
      int requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount < 3) {
          return jsonBody({'error': 'Server error'}, statusCode: 500, statusMessage: 'Internal Server Error');
        }
        return jsonBody({'data': 'success_attempt_3'});
      });

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          maxRetries: 3,
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/items');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'data': 'success_attempt_3'}));
      expect(requestCount, equals(3)); // 1 initial + 2 retries
    });

    test('3. Max retries exhausted: returns final normalized 503 response envelope', () async {
      int requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        return jsonBody({'error': 'Persistent down'}, statusCode: 503, statusMessage: 'Service Unavailable');
      });

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          maxRetries: 2,
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/down');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(503));
      expect(response.responseData, equals({'error': 'Persistent down'}));
      expect(requestCount, equals(3)); // 1 initial + 2 retries (total 3 attempts)
    });

    test('4. Transport error: connectionTimeout succeeds on retry', () async {
      int requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            message: 'Connection timed out',
          );
        }
        return jsonBody({'connected': true});
      });

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          maxRetries: 2,
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/timeout-test');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(requestCount, equals(2));
    });

    test('5. Cancellation during retry delay aborts immediately', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'error': '503'}, statusCode: 503);
      });

      final cancelToken = CancelToken();

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          maxRetries: 3,
          delayCalculator: (attempt, i, m, mult, j, err) => const Duration(seconds: 10),
        ),
      );

      final future = bolt.get('/cancel-test', cancelToken: cancelToken);

      // Yield event loop to let it hit 503 and enter retry delay
      await Future.delayed(const Duration(milliseconds: 20));

      cancelToken.cancel('User cancelled during backoff');

      final response = await future;

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.message, contains('Request was cancelled'));
    });

    test('6. Preserves RequestOptions across retries', () async {
      int requestCount = 0;
      RequestOptions? retriedOptions;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          return jsonBody({'error': '502'}, statusCode: 502);
        }
        retriedOptions = options;
        return jsonBody({'preserved': true});
      });

      final bolt = DioBolt(
        dio: dio,
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      await bolt.post(
        '/preserve',
        data: {'payload': 123},
        queryParameters: {'filter': 'all'},
        headers: {'X-Custom-Header': 'val'},
        options: Options().copyWithRetry(enabled: true),
      );

      expect(requestCount, equals(2));
      expect(retriedOptions?.path, equals('/preserve'));
      expect(retriedOptions?.queryParameters, equals({'filter': 'all'}));
      expect(retriedOptions?.headers['X-Custom-Header'], equals('val'));
      expect(retriedOptions?.data, equals({'payload': 123}));
    });

    test('7. Multiple DioBolt instances have isolated retry states', () async {
      int countA = 0;
      int countB = 0;

      final dioA = Dio(BaseOptions(baseUrl: 'https://api.a.com'));
      dioA.httpClientAdapter = MockAdapter((options) async {
        countA++;
        if (countA == 1) return jsonBody({'error': '503'}, statusCode: 503);
        return jsonBody({'ok': 'A'});
      });

      final dioB = Dio(BaseOptions(baseUrl: 'https://api.b.com'));
      dioB.httpClientAdapter = MockAdapter((options) async {
        countB++;
        return jsonBody({'ok': 'B'});
      });

      final boltA = DioBolt(
        dio: dioA,
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final boltB = DioBolt(
        dio: dioB,
      );

      await boltA.get('/test');
      await boltB.get('/test');

      expect(countA, equals(2)); // Retried once
      expect(countB, equals(1)); // No retry
    });
  });

  group('DioBoltRetryInterceptor - Auth & Retry Interaction Flows', () {
    test('Flow A: 503 -> network retry -> 200 (Auth does not interfere)', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          return jsonBody({'error': '503'}, statusCode: 503);
        }
        return jsonBody({'result': 'recovered'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'auth-token',
          refreshToken: (_) {
            refreshCount++;
            return 'new-token';
          },
        ),
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/flow-a');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(requestCount, equals(2));
      expect(refreshCount, equals(0)); // Auth was not triggered on 503
    });

    test('Flow B: 401 -> auth refresh -> auth retry -> 200 (Network retry does not interfere)', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (options.headers['Authorization'] == 'Bearer initial-token') {
          return jsonBody({'error': '401'}, statusCode: 401);
        }
        return jsonBody({'user': 'refreshed_user'});
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
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/flow-b');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(requestCount, equals(2));
      expect(refreshCount, equals(1)); // Exactly 1 auth refresh
    });

    test('Flow C: 503 -> network retry -> 401 -> auth refresh -> auth retry -> 200', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          // Attempt 1 fails with 503 (transient network glitch)
          return jsonBody({'error': '503'}, statusCode: 503);
        } else if (requestCount == 2) {
          // Network retry connects, but server says token is 401 expired
          return jsonBody({'error': '401'}, statusCode: 401);
        }
        // Auth retry with fresh token succeeds
        return jsonBody({'token_used': options.headers['Authorization']});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'old-token',
          refreshToken: (_) {
            refreshCount++;
            return 'fresh-token';
          },
        ),
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/flow-c');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData['token_used'], equals('Bearer fresh-token'));
      expect(requestCount, equals(3)); // 1 initial + 1 network retry + 1 auth retry
      expect(refreshCount, equals(1));
    });

    test('Flow D: 401 -> auth refresh -> auth retry -> 503 -> network retry -> 200', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          // Initial request fails with 401
          return jsonBody({'error': '401'}, statusCode: 401);
        } else if (requestCount == 2) {
          // Auth retry runs with new token, but hits 503 transient gateway glitch
          return jsonBody({'error': '503'}, statusCode: 503);
        }
        // Network retry succeeds
        return jsonBody({'completed': true, 'token': options.headers['Authorization']});
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
        retryConfig: DioBoltRetryConfig(
          delayCalculator: (attempt, i, m, mult, j, err) => Duration.zero,
        ),
      );

      final response = await bolt.get('/flow-d');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData['token'], equals('Bearer token-2'));
      expect(requestCount, equals(3)); // 1 initial + 1 auth retry + 1 network retry
      expect(refreshCount, equals(1));
    });
  });
}
