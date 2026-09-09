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

ResponseBody jsonResponseBody(
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

ResponseBody emptyResponseBody({
  int statusCode = 204,
  String statusMessage = 'No Content',
}) {
  return ResponseBody(
    Stream<Uint8List>.empty(),
    statusCode,
    statusMessage: statusMessage,
    headers: {},
  );
}

void main() {
  group('DioBolt Logging - Request logging', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;

    setUp(() {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonResponseBody({'success': true});
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: false,
          logPrint: (msg) => logs.add(msg),
        ),
      );
    });

    test('1. GET request logs method, url, path, query params, headers, and payload: none', () async {
      await bolt.get(
        '/users',
        queryParameters: {'page': 1, 'limit': 20},
        headers: {'X-Custom-Header': 'CustomValue'},
      );

      expect(logs, hasLength(2)); // [0] request, [1] response
      final requestLog = logs[0];

      expect(requestLog, contains('🚀 DIO BOLT • REQUEST [#1]'));
      expect(requestLog, contains('METHOD   : GET'));
      expect(requestLog, contains('URL      : https://api.example.com/users?page=1&limit=20'));
      expect(requestLog, contains('PATH     : /users'));
      expect(requestLog, contains('"page": 1'));
      expect(requestLog, contains('"limit": 20'));
      expect(requestLog, contains('"X-Custom-Header": "CustomValue"'));
      expect(requestLog, contains('PAYLOAD  : none'));
    });

    test('2. POST request with JSON payload logs complete payload', () async {
      await bolt.post(
        '/users',
        data: {
          'name': 'Rahim',
          'email': 'rahim@example.com',
          'role': 'developer',
        },
      );

      expect(logs, hasLength(2));
      final requestLog = logs[0];
      expect(requestLog, contains('🚀 DIO BOLT • REQUEST [#1]'));
      expect(requestLog, contains('METHOD   : POST'));
      expect(requestLog, contains('"name": "Rahim"'));
      expect(requestLog, contains('"email": "rahim@example.com"'));
      expect(requestLog, contains('"role": "developer"'));
    });
  });

  group('DioBolt Logging - Success response logging (2xx)', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;

    void setupMockAdapter(int statusCode, String statusMessage, dynamic responseData) {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        if (statusCode == 204 || responseData == null) {
          return emptyResponseBody(statusCode: statusCode, statusMessage: statusMessage);
        }
        return jsonResponseBody(responseData, statusCode: statusCode, statusMessage: statusMessage);
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: false,
          logPrint: (msg) => logs.add(msg),
        ),
      );
    }

    test('200 OK logs status, duration, and complete response data', () async {
      setupMockAdapter(200, 'OK', {
        'id': 101,
        'name': 'Rahim',
        'meta': {'tier': 'pro'},
      });

      await bolt.get('/users/101');

      expect(logs, hasLength(2));
      final responseLog = logs[1];
      expect(responseLog, contains('✅ DIO BOLT • RESPONSE [#1]'));
      expect(responseLog, contains('STATUS        : 200 OK'));
      expect(responseLog, contains('DURATION      :'));
      expect(responseLog, contains('"id": 101'));
      expect(responseLog, contains('"name": "Rahim"'));
      expect(responseLog, contains('"tier": "pro"'));
    });

    test('201 Created logs status and created response', () async {
      setupMockAdapter(201, 'Created', {'id': 202, 'created': true});

      await bolt.post('/users', data: {'name': 'New User'});

      expect(logs, hasLength(2));
      final responseLog = logs[1];
      expect(responseLog, contains('✅ DIO BOLT • RESPONSE [#1]'));
      expect(responseLog, contains('STATUS        : 201 Created'));
      expect(responseLog, contains('"id": 202'));
    });

    test('204 No Content logs null response data cleanly', () async {
      setupMockAdapter(204, 'No Content', null);

      await bolt.delete('/users/202');

      expect(logs, hasLength(2));
      final responseLog = logs[1];
      expect(responseLog, contains('✅ DIO BOLT • RESPONSE [#1]'));
      expect(responseLog, contains('STATUS        : 204 No Content'));
      expect(responseLog, contains('RESPONSE DATA :'));
      expect(responseLog, contains('null'));
    });
  });

  group('DioBolt Logging - HTTP error response logging (4xx / 5xx in RED)', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;

    void setupErrorAdapter(int statusCode, String statusMessage, dynamic data) {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonResponseBody(data, statusCode: statusCode, statusMessage: statusMessage);
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: true, // ANSI red color
          logPrint: (msg) => logs.add(msg),
        ),
      );
    }

    test('401 Unauthorized produces RED HTTP response log', () async {
      setupErrorAdapter(401, 'Unauthorized', {'success': false, 'message': 'Token expired'});

      final response = await bolt.get('/protected');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(logs, hasLength(2));

      final errorLog = logs[1];
      expect(errorLog, contains('\x1B[31m')); // Red color code
      expect(errorLog, contains('❌ DIO BOLT • RESPONSE [#1]'));
      expect(errorLog, contains('STATUS        : 401 Unauthorized'));
      expect(errorLog, contains('"Token expired"'));
      expect(errorLog, contains('\x1B[0m')); // Reset color code
    });

    test('422 Unprocessable Entity logs complete validation errors in RED', () async {
      final validationData = {
        'success': false,
        'message': 'Validation failed',
        'errors': {
          'email': ['Email format is invalid'],
          'password': ['Password is too short'],
        },
      };
      setupErrorAdapter(422, 'Unprocessable Entity', validationData);

      await bolt.post('/register', data: {});

      expect(logs, hasLength(2));
      final errorLog = logs[1];
      expect(errorLog, contains('\x1B[31m')); // Red color code
      expect(errorLog, contains('❌ DIO BOLT • RESPONSE [#1]'));
      expect(errorLog, contains('STATUS        : 422 Unprocessable Entity'));
      expect(errorLog, contains('"Email format is invalid"'));
      expect(errorLog, contains('"Password is too short"'));
    });

    test('500 Server Error logs server error in RED', () async {
      setupErrorAdapter(500, 'Internal Server Error', {'error': 'Database timeout'});

      await bolt.get('/users');

      expect(logs, hasLength(2));
      final errorLog = logs[1];
      expect(errorLog, contains('\x1B[31m'));
      expect(errorLog, contains('STATUS        : 500 Internal Server Error'));
      expect(errorLog, contains('"Database timeout"'));
    });
  });

  group('DioBolt Logging - Transport and network failure logging', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;

    void setupTransportErrorAdapter(DioExceptionType errorType, {String? message}) {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: errorType,
          message: message,
        );
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: true,
          logPrint: (msg) => logs.add(msg),
        ),
      );
    }

    test('connectionTimeout produces RED network error log without invented status code', () async {
      setupTransportErrorAdapter(DioExceptionType.connectionTimeout);

      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(logs, hasLength(2));

      final errorLog = logs[1];
      expect(errorLog, contains('\x1B[31m'));
      expect(errorLog, contains('❌ DIO BOLT • NETWORK ERROR [#1]'));
      expect(errorLog, contains('ERROR TYPE : connectionTimeout'));
      expect(errorLog, contains('STATUS     : No HTTP response'));
      expect(errorLog, contains('MESSAGE    : Connection timed out'));
    });

    test('connectionError (no internet) produces RED network error log', () async {
      setupTransportErrorAdapter(DioExceptionType.connectionError);

      await bolt.get('/test');

      expect(logs, hasLength(2));
      final errorLog = logs[1];
      expect(errorLog, contains('❌ DIO BOLT • NETWORK ERROR [#1]'));
      expect(errorLog, contains('ERROR TYPE : connectionError'));
      expect(errorLog, contains('MESSAGE    : Unable to connect to the server'));
    });

    test('cancel produces RED network error log', () async {
      setupTransportErrorAdapter(DioExceptionType.cancel);

      await bolt.get('/test');

      expect(logs, hasLength(2));
      final errorLog = logs[1];
      expect(errorLog, contains('❌ DIO BOLT • NETWORK ERROR [#1]'));
      expect(errorLog, contains('ERROR TYPE : cancel'));
      expect(errorLog, contains('MESSAGE    : Request was cancelled'));
    });

    test('badCertificate produces RED network error log', () async {
      setupTransportErrorAdapter(DioExceptionType.badCertificate);

      await bolt.get('/test');

      expect(logs, hasLength(2));
      final errorLog = logs[1];
      expect(errorLog, contains('❌ DIO BOLT • NETWORK ERROR [#1]'));
      expect(errorLog, contains('ERROR TYPE : badCertificate'));
      expect(errorLog, contains('MESSAGE    : Secure connection could not be established'));
    });
  });

  group('DioBolt Logging - Security & Sensitive Data Sanitization', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;
    late RequestOptions capturedOptions;

    setUp(() {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        capturedOptions = options;
        return jsonResponseBody({'ok': true});
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: false,
          logPrint: (msg) => logs.add(msg),
        ),
      );
    });

    test('Redacts sensitive headers and payload fields while preserving actual request options', () async {
      await bolt.post(
        '/login',
        headers: {
          'Authorization': 'Bearer secret-jwt-token-12345',
          'X-Api-Key': 'my-super-secret-api-key',
          'X-Public-Header': 'public-value',
        },
        data: {
          'username': 'rahim',
          'password': 'SuperSecretPassword123!',
          'refresh_token': 'secret-refresh-token',
        },
      );

      final requestLog = logs[0];

      // Console log must have [REDACTED]
      expect(requestLog, contains('"Authorization": "[REDACTED]"'));
      expect(requestLog, contains('"X-Api-Key": "[REDACTED]"'));
      expect(requestLog, contains('"X-Public-Header": "public-value"'));
      expect(requestLog, contains('"password": "[REDACTED]"'));
      expect(requestLog, contains('"refresh_token": "[REDACTED]"'));
      expect(requestLog, contains('"username": "rahim"'));

      // Secrets must NOT leak into the log
      expect(requestLog, isNot(contains('secret-jwt-token-12345')));
      expect(requestLog, isNot(contains('my-super-secret-api-key')));
      expect(requestLog, isNot(contains('SuperSecretPassword123!')));
      expect(requestLog, isNot(contains('secret-refresh-token')));

      // Actual network request options must NOT be mutated
      expect(capturedOptions.headers['Authorization'], equals('Bearer secret-jwt-token-12345'));
      expect(capturedOptions.headers['X-Api-Key'], equals('my-super-secret-api-key'));
      final actualData = capturedOptions.data as Map<String, dynamic>;
      expect(actualData['password'], equals('SuperSecretPassword123!'));
    });
  });

  group('DioBolt Logging - Special Payloads & Safety', () {
    late List<String> logs;
    late Dio dio;
    late DioBolt bolt;

    setUp(() {
      logs = [];
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonResponseBody({'uploaded': true});
      });

      bolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          useColors: false,
          logPrint: (msg) => logs.add(msg),
        ),
      );
    });

    test('Handles FormData and MultipartFile safely without dumping binary content', () async {
      final formData = FormData.fromMap({
        'name': 'Rahim',
        'password': 'secret_password',
        'avatar': MultipartFile.fromBytes([0, 1, 2, 3], filename: 'avatar.png'),
      });

      await bolt.post('/upload', data: formData);

      final requestLog = logs[0];
      expect(requestLog, contains('FormData'));
      expect(requestLog, contains('name: Rahim'));
      expect(requestLog, contains('password: [REDACTED]'));
      expect(requestLog, contains('avatar: MultipartFile [filename: avatar.png, length: 4 bytes'));
    });

    test('Handles binary request and response data safely', () async {
      final binaryBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

      dio.httpClientAdapter = MockAdapter((options) async {
        return ResponseBody(
          Stream.value(binaryBytes),
          200,
          statusMessage: 'OK',
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        );
      });

      await bolt.post(
        '/binary',
        data: binaryBytes,
        options: Options(responseType: ResponseType.bytes),
      );

      final requestLog = logs[0];
      final responseLog = logs[1];

      expect(requestLog, contains('PAYLOAD  : <binary data: 6 B>'));
      expect(responseLog, contains('RESPONSE DATA :'));
      expect(responseLog, contains('<binary data: 6 B>'));
    });

    test('Zero-crash guarantee: Logging formatting or printer errors do not crash the request', () async {
      final crashingBolt = DioBolt(
        dio: dio,
        logConfig: DioBoltLogConfig(
          enabled: true,
          logPrint: (msg) => throw Exception('Printer crashed unexpectedly'),
        ),
      );

      final response = await crashingBolt.post('/unusual', data: {'valid': true});

      // Request must succeed completely without crashing despite logger throwing
      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'uploaded': true}));
    });
  });

  group('DioBolt Logging - Disabled state', () {
    test('Does not log when enabled: false or enableLogging: false', () async {
      final logs = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = MockAdapter((options) async {
        return jsonResponseBody({'ok': true});
      });

      final bolt = DioBolt(
        dio: dio,
        enableLogging: false,
        logConfig: DioBoltLogConfig(
          enabled: false,
          logPrint: (msg) => logs.add(msg),
        ),
      );

      await bolt.get('/test');

      expect(logs, isEmpty);
    });
  });
}
