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
  group('DioBoltAuth - Token Injection', () {
    test('1. Injects access token as Authorization: Bearer <token>', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'access-token-123',
          refreshToken: (_) => 'new-token',
        ),
      );

      final response = await bolt.get('/protected');

      expect(response.isSuccess, isTrue);
      expect(captured?.headers['Authorization'], equals('Bearer access-token-123'));
    });

    test('2. Does not inject header when token is null', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => null,
          refreshToken: (_) => 'new-token',
        ),
      );

      await bolt.get('/public');

      expect(captured?.headers.containsKey('Authorization'), isFalse);
    });

    test('3. Does not inject header when token is empty string', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => '',
          refreshToken: (_) => 'new-token',
        ),
      );

      await bolt.get('/public');

      expect(captured?.headers.containsKey('Authorization'), isFalse);
    });

    test('4. Injects custom headerKey and uses tokenHeaderBuilder', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'key-abc',
          refreshToken: (_) => 'new-key',
          headerKey: 'X-API-TOKEN',
          tokenHeaderBuilder: (token) => 'Token $token',
        ),
      );

      await bolt.get('/custom');

      expect(captured?.headers['X-API-TOKEN'], equals('Token key-abc'));
    });
  });

  group('DioBoltAuth - Header Precedence & Case-Insensitivity', () {
    test('1. Preserves explicitly supplied Authorization header on initial request', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'auto-token',
          refreshToken: (_) => 'new-token',
        ),
      );

      await bolt.get(
        '/endpoint',
        headers: {'Authorization': 'Bearer custom-explicit-token'},
      );

      expect(captured?.headers['Authorization'], equals('Bearer custom-explicit-token'));
    });

    test('2. Case-insensitively detects explicit authorization header', () async {
      RequestOptions? captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        captured = options;
        return jsonBody({'status': 'ok'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'auto-token',
          refreshToken: (_) => 'new-token',
        ),
      );

      await bolt.get(
        '/endpoint',
        headers: {'authorization': 'Bearer lowercase-token'},
      );

      expect(captured?.headers['authorization'], equals('Bearer lowercase-token'));
      expect(captured?.headers['authorization'], isNot(contains('auto-token')));
    });

    test('3. Explicit Authorization participates in 401 refresh and retry updates to new token', () async {
      int requestCount = 0;
      final capturedHeaders = <Map<String, dynamic>>[];

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        capturedHeaders.add(Map.from(options.headers));
        if (requestCount == 1) {
          return jsonBody({'error': 'Unauthorized'}, statusCode: 401, statusMessage: 'Unauthorized');
        }
        return jsonBody({'data': 'success_after_refresh'});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'auto-token-1',
          refreshToken: (_) => 'refreshed-token-2',
        ),
      );

      final response = await bolt.get(
        '/protected',
        headers: {'Authorization': 'Bearer explicit-initial-token'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(requestCount, equals(2));

      // Initial request used explicit token
      expect(capturedHeaders[0]['Authorization'], equals('Bearer explicit-initial-token'));
      // Retried request updated to freshly minted token
      expect(capturedHeaders[1]['Authorization'], equals('Bearer refreshed-token-2'));
    });
  });

  group('DioBoltAuth - skipAuth Behavior', () {
    test('skipAuth: true bypasses token injection and 401 refresh', () async {
      int requestCount = 0;
      int refreshCallCount = 0;
      RequestOptions? capturedOptions;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        capturedOptions = options;
        return jsonBody({'error': 'Unauthorized'}, statusCode: 401, statusMessage: 'Unauthorized');
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'access-token',
          refreshToken: (_) {
            refreshCallCount++;
            return 'new-token';
          },
        ),
      );

      final response = await bolt.post(
        '/login',
        data: {'user': 'test'},
        options: Options().copyWithSkipAuth(),
      );

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(capturedOptions?.headers.containsKey('Authorization'), isFalse);
      expect(requestCount, equals(1));
      expect(refreshCallCount, equals(0));
    });
  });

  group('DioBoltAuth - 401 Refresh & Retry Lifecycle', () {
    test('Single 401 refreshes token, calls onTokenRefreshed, and retries successfully', () async {
      int requestCount = 0;
      int refreshCount = 0;
      String? persistedToken;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          return jsonBody({'message': 'token expired'}, statusCode: 401, statusMessage: 'Unauthorized');
        }
        return jsonBody({'user': 'Alice', 'token_received': options.headers['Authorization']});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'old-token',
          refreshToken: (_) async {
            refreshCount++;
            return 'new-token-999';
          },
          onTokenRefreshed: (newToken) async {
            persistedToken = newToken;
          },
        ),
      );

      final response = await bolt.get('/profile');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData['token_received'], equals('Bearer new-token-999'));
      expect(refreshCount, equals(1));
      expect(persistedToken, equals('new-token-999'));
      expect(requestCount, equals(2));
    });

    test('Retry-once protection: retried request receiving 401 does NOT trigger second refresh', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        return jsonBody({'error': 'Persistent 401'}, statusCode: 401, statusMessage: 'Unauthorized');
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

      final response = await bolt.get('/always-401');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(response.responseData, equals({'error': 'Persistent 401'}));
      expect(requestCount, equals(2)); // initial + 1 retry
      expect(refreshCount, equals(1)); // exactly 1 refresh, no infinite loop
    });
  });

  group('DioBoltAuth - Single-Flight Concurrency & Exactly-Once Callback', () {
    test('5 concurrent 401 requests trigger exactly 1 refresh call and all 5 succeed', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (options.headers['Authorization'] == 'Bearer initial-token') {
          return jsonBody({'error': 'Expired'}, statusCode: 401, statusMessage: 'Unauthorized');
        }
        return jsonBody({'result': 'success', 'path': options.path});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'initial-token',
          refreshToken: (_) async {
            refreshCount++;
            await Future.delayed(const Duration(milliseconds: 50));
            return 'refreshed-token';
          },
        ),
      );

      final futures = [
        bolt.get('/req-1'),
        bolt.get('/req-2'),
        bolt.get('/req-3'),
        bolt.get('/req-4'),
        bolt.get('/req-5'),
      ];

      final responses = await Future.wait(futures);

      expect(refreshCount, equals(1)); // Single-flight: exactly 1 refresh HTTP call
      expect(responses, hasLength(5));
      for (final res in responses) {
        expect(res.isSuccess, isTrue);
        expect(res.statusCode, equals(200));
        expect(res.responseData['result'], equals('success'));
      }
      expect(requestCount, equals(10)); // 5 initial + 5 retries
    });

    test('10 concurrent 401 requests with refresh failure invoke onRefreshFailed EXACTLY ONCE', () async {
      int refreshCount = 0;
      int onRefreshFailedCount = 0;
      DioBoltResponse? failureResponseReceived;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'code': 'SESSION_EXPIRED'}, statusCode: 401, statusMessage: 'Unauthorized');
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) async {
            refreshCount++;
            await Future.delayed(const Duration(milliseconds: 30));
            return null; // Refresh failed
          },
          onRefreshFailed: (resp) {
            onRefreshFailedCount++;
            failureResponseReceived = resp;
          },
        ),
      );

      final futures = List.generate(10, (i) => bolt.get('/req-$i'));
      final responses = await Future.wait(futures);

      expect(refreshCount, equals(1));
      expect(onRefreshFailedCount, equals(1)); // Exactly-once per refresh cycle!
      expect(failureResponseReceived?.statusCode, equals(401));
      expect(failureResponseReceived?.responseData, equals({'code': 'SESSION_EXPIRED'}));

      for (final res in responses) {
        expect(res.isSuccess, isFalse);
        expect(res.statusCode, equals(401));
        expect(res.responseData, equals({'code': 'SESSION_EXPIRED'}));
      }
    });

    test('Single-flight state resets cleanly after failure allowing subsequent wave to retry', () async {
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer valid-wave-2-token') {
          return jsonBody({'ok': true});
        }
        return jsonBody({'error': '401'}, statusCode: 401);
      });

      String currentToken = 'stale-token';

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => currentToken,
          refreshToken: (_) async {
            refreshCount++;
            if (refreshCount == 1) return null; // Wave 1 fails
            return 'valid-wave-2-token'; // Wave 2 succeeds
          },
        ),
      );

      // Wave 1
      final wave1 = await bolt.get('/wave1');
      expect(wave1.isSuccess, isFalse);
      expect(refreshCount, equals(1));

      // Wave 2
      final wave2 = await bolt.get('/wave2');
      expect(wave2.isSuccess, isTrue);
      expect(refreshCount, equals(2));
    });
  });

  group('DioBoltAuth - Failure Semantics & Strict Persistence', () {
    test('Strict Persistence: when onTokenRefreshed throws, refresh is deemed FAILED', () async {
      int onRefreshFailedCalls = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) => 'new-unpersisted-token',
          onTokenRefreshed: (token) {
            throw Exception('Disk full: cannot write to secure storage');
          },
          onRefreshFailed: (_) => onRefreshFailedCalls++,
        ),
      );

      final response = await bolt.get('/profile');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(onRefreshFailedCalls, equals(1));
    });

    test('refreshToken returning empty string is treated as failure', () async {
      int onRefreshFailedCalls = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) => '',
          onRefreshFailed: (_) => onRefreshFailedCalls++,
        ),
      );

      final response = await bolt.get('/profile');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(onRefreshFailedCalls, equals(1));
    });

    test('refreshToken throwing exception is caught safely and does not escape public API', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) => throw Exception('Network socket died during refresh'),
        ),
      );

      final response = await bolt.get('/profile');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
    });

    test('onRefreshFailed throwing exception does not escape public API', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'error': 'Unauthorized'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) => null,
          onRefreshFailed: (_) => throw Exception('Crash inside logout callback'),
        ),
      );

      final response = await bolt.get('/profile');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
    });
  });

  group('DioBoltAuth - Cancellation Safety & Independence', () {
    test('Cancellation while waiting for refresh unblocks cancelled request immediately without stopping shared refresh', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      final refreshCompleter = Completer<String?>();

      dio.httpClientAdapter = MockAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer new-token') {
          return jsonBody({'ok': true});
        }
        return jsonBody({'error': '401'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'old-token',
          refreshToken: (_) => refreshCompleter.future,
        ),
      );

      final cancelTokenA = CancelToken();

      final futureA = bolt.get('/req-a', cancelToken: cancelTokenA);
      final futureB = bolt.get('/req-b');

      // Yield event loop to let both hit 401 and start waiting
      await Future.delayed(const Duration(milliseconds: 10));

      // Cancel request A while refresh is pending
      cancelTokenA.cancel('User aborted request A');

      // Request A should unblock immediately
      final responseA = await futureA;
      expect(responseA.isSuccess, isFalse);
      expect(responseA.statusCode, equals(0));
      expect(responseA.message, contains('Request was cancelled'));

      // Now complete the shared refresh
      refreshCompleter.complete('new-token');

      // Request B must continue and succeed
      final responseB = await futureB;
      expect(responseB.isSuccess, isTrue);
      expect(responseB.statusCode, equals(200));
    });
  });

  group('DioBoltAuth - Payload Replayability', () {
    test('Replays Map and JSON payloads on retry', () async {
      int count = 0;
      dynamic receivedData;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        count++;
        receivedData = options.data;
        if (count == 1) return jsonBody({'error': '401'}, statusCode: 401);
        return jsonBody({'created': true});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 't1',
          refreshToken: (_) => 't2',
        ),
      );

      final response = await bolt.post('/create', data: {'name': 'Charlie'});

      expect(response.isSuccess, isTrue);
      expect(count, equals(2));
      expect(receivedData, equals({'name': 'Charlie'}));
    });

    test('Replays Uint8List byte payload on retry', () async {
      int count = 0;
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        count++;
        if (count == 1) return jsonBody({'error': '401'}, statusCode: 401);
        return jsonBody({'bytes_received': true});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 't1',
          refreshToken: (_) => 't2',
        ),
      );

      final response = await bolt.post('/bytes', data: bytes);

      expect(response.isSuccess, isTrue);
      expect(count, equals(2));
    });

    test('Replays FormData payload via clone', () async {
      int count = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        count++;
        if (count == 1) return jsonBody({'error': '401'}, statusCode: 401);
        return jsonBody({'uploaded': true});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 't1',
          refreshToken: (_) => 't2',
        ),
      );

      final formData = FormData.fromMap({
        'title': 'Avatar',
        'file': MultipartFile.fromBytes([10, 20, 30], filename: 'avatar.png'),
      });

      final response = await bolt.post('/upload', data: formData);

      expect(response.isSuccess, isTrue);
      expect(count, equals(2));
    });

    test('Stream payload is NOT retried and returns original 401 response', () async {
      int count = 0;
      final stream = Stream<List<int>>.value([1, 2, 3]);

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        count++;
        return jsonBody({'error': 'Stream auth failed'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 't1',
          refreshToken: (_) => 't2',
        ),
      );

      final response = await bolt.post('/stream', data: stream);

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(response.responseData, equals({'error': 'Stream auth failed'}));
      expect(count, equals(1)); // Stream not retried for safety
    });
  });

  group('DioBoltAuth - Isolated Refresh Client & Multi-Instance', () {
    test('Refresh client 401 does not trigger recursive refresh loop', () async {
      int mainCount = 0;
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCount++;
          return jsonBody({'error': 'Refresh token also expired'}, statusCode: 401);
        }
        mainCount++;
        return jsonBody({'error': 'Access token expired'}, statusCode: 401);
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'expired-access',
          refreshToken: (refreshClient) async {
            // Calling the refresh endpoint using the isolated client
            final res = await refreshClient.post('/auth/refresh');
            if (res.statusCode == 200) return res.data['token'];
            return null;
          },
        ),
      );

      final response = await bolt.get('/protected');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(mainCount, equals(1));
      expect(refreshCount, equals(1)); // Executed once, no recursion!
    });

    test('Multiple DioBolt instances have independent refresh locks', () async {
      int refreshCountA = 0;
      int refreshCountB = 0;

      final dioA = Dio(BaseOptions(baseUrl: 'https://api.a.com'));
      dioA.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'ok': 'A'});
      });

      final dioB = Dio(BaseOptions(baseUrl: 'https://api.b.com'));
      dioB.httpClientAdapter = MockAdapter((options) async {
        return jsonBody({'ok': 'B'});
      });

      final boltA = DioBolt(
        dio: dioA,
        auth: DioBoltAuth(
          getAccessToken: () => 'token-A',
          refreshToken: (_) {
            refreshCountA++;
            return 'new-A';
          },
        ),
      );

      final boltB = DioBolt(
        dio: dioB,
        auth: DioBoltAuth(
          getAccessToken: () => 'token-B',
          refreshToken: (_) {
            refreshCountB++;
            return 'new-B';
          },
        ),
      );

      await boltA.get('/test');
      await boltB.get('/test');

      expect(boltA.dio, isNot(same(boltB.dio)));
      expect(refreshCountA, equals(0));
      expect(refreshCountB, equals(0));
    });
  });

  group('DioBoltAuth - Retry Options Preservation', () {
    test('Preserves query parameters, custom headers, contentType, and extra on retry', () async {
      int count = 0;
      RequestOptions? retriedOptions;

      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        count++;
        if (count == 1) return jsonBody({'error': '401'}, statusCode: 401);
        retriedOptions = options;
        return jsonBody({'success': true});
      });

      final bolt = DioBolt(
        dio: dio,
        auth: DioBoltAuth(
          getAccessToken: () => 'token-1',
          refreshToken: (_) => 'token-2',
        ),
      );

      final customOptions = Options(
        headers: {'X-Custom-Tracking': 'track-99'},
        contentType: 'application/custom+json',
        extra: {'featureFlag': 'v2'},
      );

      await bolt.post(
        '/submit',
        data: {'key': 'val'},
        queryParameters: {'filter': 'active'},
        options: customOptions,
      );

      expect(count, equals(2));
      expect(retriedOptions?.queryParameters, equals({'filter': 'active'}));
      expect(retriedOptions?.headers['X-Custom-Tracking'], equals('track-99'));
      expect(retriedOptions?.headers['Authorization'], equals('Bearer token-2'));
      expect(retriedOptions?.contentType, equals('application/custom+json'));
      expect(retriedOptions?.extra['featureFlag'], equals('v2'));
    });
  });
}
