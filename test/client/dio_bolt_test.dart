import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:test/test.dart';

void main() {
  group('DioBolt foundation', () {
    test('instantiates with default Dio instance', () {
      final bolt = DioBolt();
      expect(bolt.dio, isNotNull);
      expect(bolt.dio, isA<Dio>());
    });

    test('accepts custom Dio instance', () {
      final customDio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      final bolt = DioBolt(dio: customDio);
      expect(bolt.dio, same(customDio));
      expect(bolt.dio.options.baseUrl, equals('https://api.example.com'));
    });

    test('accepts custom BaseOptions', () {
      final options = BaseOptions(
        baseUrl: 'https://example.com/api',
        connectTimeout: const Duration(seconds: 5),
      );
      final bolt = DioBolt(options: options);
      expect(bolt.dio.options.baseUrl, equals('https://example.com/api'));
      expect(
        bolt.dio.options.connectTimeout,
        equals(const Duration(seconds: 5)),
      );
    });
  });

  group('DioBolt Raw API - Success HTTP responses (2xx)', () {
    late Dio dio;
    late DioBolt bolt;
    RequestOptions? capturedOptions;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      capturedOptions = null;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;

            if (options.path == '/status/200' && options.method == 'GET') {
              options.onReceiveProgress?.call(100, 100);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'id': 1, 'name': 'Alice'},
                ),
              );
            }

            if (options.path == '/status/201' && options.method == 'POST') {
              options.onSendProgress?.call(50, 100);
              options.onReceiveProgress?.call(100, 100);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  statusMessage: 'Created',
                  data: {'id': 2, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/status/200' && options.method == 'PUT') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'id': 2, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/status/200' && options.method == 'PATCH') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'id': 2, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/status/204' && options.method == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 204,
                  statusMessage: 'No Content',
                  data: null,
                ),
              );
            }

            if (options.path == '/paginated' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {
                    'success': true,
                    'data': [
                      {'id': 1, 'name': 'Alice'},
                      {'id': 2, 'name': 'Bob'},
                    ],
                    'pagination': {
                      'page': 1,
                      'total': 100,
                    },
                  },
                ),
              );
            }

            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: options.data,
              ),
            );
          },
        ),
      );

      bolt = DioBolt(dio: dio);
    });

    test('200 GET returns DioBoltResponse with isSuccess: true', () async {
      final response = await bolt.get('/status/200');

      expect(response, isA<DioBoltResponse>());
      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.message, equals('OK'));
      expect(response.responseData, equals({'id': 1, 'name': 'Alice'}));
      expect(capturedOptions?.method, equals('GET'));
    });

    test('201 POST returns DioBoltResponse with isSuccess: true', () async {
      final response = await bolt.post(
        '/status/201',
        data: {'name': 'Bob'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(201));
      expect(response.message, equals('Created'));
      expect(response.responseData, equals({'id': 2, 'name': 'Bob'}));
      expect(capturedOptions?.method, equals('POST'));
    });

    test('200 PUT returns DioBoltResponse with isSuccess: true', () async {
      final response = await bolt.put(
        '/status/200',
        data: {'name': 'Bob Updated'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'id': 2, 'name': 'Bob Updated'}));
      expect(capturedOptions?.method, equals('PUT'));
    });

    test('200 PATCH returns DioBoltResponse with isSuccess: true', () async {
      final response = await bolt.patch(
        '/status/200',
        data: {'name': 'Bob Patched'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'id': 2, 'name': 'Bob Patched'}));
      expect(capturedOptions?.method, equals('PATCH'));
    });

    test('204 DELETE returns DioBoltResponse with isSuccess: true and null responseData', () async {
      final response = await bolt.delete('/status/204');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(204));
      expect(response.message, equals('No Content'));
      expect(response.responseData, isNull);
      expect(capturedOptions?.method, equals('DELETE'));
    });

    test('Preserves complete complex nested structure without reduction', () async {
      final response = await bolt.get('/paginated');

      expect(response.isSuccess, isTrue);
      expect(response.responseData, isA<Map<String, dynamic>>());
      final map = response.responseData as Map<String, dynamic>;
      expect(map['success'], isTrue);
      expect(map['data'], hasLength(2));
      expect(map['pagination']['total'], equals(100));
    });

    test('Query parameters reach Dio correctly', () async {
      await bolt.get(
        '/status/200',
        queryParameters: {'filter': 'active', 'page': 1},
      );

      expect(capturedOptions?.queryParameters, equals({'filter': 'active', 'page': 1}));
    });

    test('Header precedence: explicit headers override Options.headers', () async {
      final options = Options(headers: {
        'Authorization': 'Bearer old-token',
        'X-Keep': 'preserved',
      });

      await bolt.get(
        '/status/200',
        options: options,
        headers: {'Authorization': 'Bearer new-token'},
      );

      expect(capturedOptions?.headers['Authorization'], equals('Bearer new-token'));
      expect(capturedOptions?.headers['X-Keep'], equals('preserved'));
    });

    test('Send progress and receive progress callbacks are triggered', () async {
      int? sentBytes;
      int? receivedBytes;

      await bolt.post(
        '/status/201',
        data: {'name': 'Progress Test'},
        onSendProgress: (sent, total) => sentBytes = sent,
        onReceiveProgress: (recv, total) => receivedBytes = recv,
      );

      expect(sentBytes, equals(50));
      expect(receivedBytes, equals(100));
    });
  });

  group('DioBolt Raw API - HTTP error responses (4xx & 5xx) never throw', () {
    late Dio dio;
    late DioBolt bolt;

    void setupErrorRoute(int statusCode, dynamic responseData, [String? statusMessage]) {
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: statusCode,
                  statusMessage: statusMessage ?? 'HTTP $statusCode',
                  data: responseData,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );
      bolt = DioBolt(dio: dio);
    }

    test('400 returns DioBoltResponse with isSuccess: false and statusCode: 400', () async {
      setupErrorRoute(400, {'error': 'Bad Request', 'field': 'email'});
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(400));
      expect(response.responseData, equals({'error': 'Bad Request', 'field': 'email'}));
      expect(response.message, equals('HTTP 400'));
    });

    test('401 returns DioBoltResponse with isSuccess: false and statusCode: 401', () async {
      setupErrorRoute(401, {'message': 'Unauthorized'});
      final response = await bolt.post('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(401));
      expect(response.responseData, equals({'message': 'Unauthorized'}));
    });

    test('403 returns DioBoltResponse with isSuccess: false and statusCode: 403', () async {
      setupErrorRoute(403, {'message': 'Forbidden'});
      final response = await bolt.put('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(403));
      expect(response.responseData, equals({'message': 'Forbidden'}));
    });

    test('404 returns DioBoltResponse with isSuccess: false and statusCode: 404', () async {
      setupErrorRoute(404, {'message': 'Not Found'});
      final response = await bolt.delete('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(404));
      expect(response.responseData, equals({'message': 'Not Found'}));
    });

    test('409 returns DioBoltResponse with isSuccess: false and statusCode: 409', () async {
      setupErrorRoute(409, {'error': 'Resource conflict'});
      final response = await bolt.patch('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(409));
      expect(response.responseData, equals({'error': 'Resource conflict'}));
    });

    test('422 preserves complete validation payload', () async {
      final validationPayload = {
        'success': false,
        'message': 'Validation failed',
        'errors': {
          'email': ['Invalid email format', 'Email already taken'],
          'password': ['Password is too short'],
        },
        'meta': {'traceId': 'req-98765'},
      };

      setupErrorRoute(422, validationPayload, 'Unprocessable Entity');
      final response = await bolt.post('/register', data: {'email': 'bad'});

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(422));
      expect(response.message, equals('Unprocessable Entity'));
      expect(response.responseData, equals(validationPayload));
      expect(response.responseData['errors']['email'], hasLength(2));
      expect(response.responseData['meta']['traceId'], equals('req-98765'));
    });

    test('429 returns DioBoltResponse with isSuccess: false and statusCode: 429', () async {
      setupErrorRoute(429, {'error': 'Too Many Requests', 'retryAfter': 60});
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(429));
      expect(response.responseData, equals({'error': 'Too Many Requests', 'retryAfter': 60}));
    });

    test('500 returns DioBoltResponse with isSuccess: false and statusCode: 500', () async {
      setupErrorRoute(500, {'error': 'Internal server error'});
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(500));
      expect(response.responseData, equals({'error': 'Internal server error'}));
    });

    test('503 returns DioBoltResponse with isSuccess: false and statusCode: 503', () async {
      setupErrorRoute(503, {'error': 'Service unavailable'});
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(503));
      expect(response.responseData, equals({'error': 'Service unavailable'}));
    });
  });

  group('DioBolt Raw API - Transport and network failures never throw', () {
    late Dio dio;
    late DioBolt bolt;

    void setupTransportError(DioExceptionType errorType, {String? customMessage}) {
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: errorType,
                message: customMessage,
              ),
            );
          },
        ),
      );
      bolt = DioBolt(dio: dio);
    }

    test('connection timeout returns statusCode: 0, isSuccess: false, message: Connection timed out.', () async {
      setupTransportError(DioExceptionType.connectionTimeout);
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Connection timed out.'));
    });

    test('send timeout returns statusCode: 0, isSuccess: false, message: Request sending timed out.', () async {
      setupTransportError(DioExceptionType.sendTimeout);
      final response = await bolt.post('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Request sending timed out.'));
    });

    test('receive timeout returns statusCode: 0, isSuccess: false, message: Response receiving timed out.', () async {
      setupTransportError(DioExceptionType.receiveTimeout);
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Response receiving timed out.'));
    });

    test('connection error (no internet / DNS) returns statusCode: 0, isSuccess: false, message: Unable to connect to the server.', () async {
      setupTransportError(DioExceptionType.connectionError);
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Unable to connect to the server.'));
    });

    test('cancel returns statusCode: 0, isSuccess: false, message: Request was cancelled.', () async {
      setupTransportError(DioExceptionType.cancel);
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Request was cancelled.'));
    });

    test('bad certificate returns statusCode: 0, isSuccess: false, message: Secure connection could not be established.', () async {
      setupTransportError(DioExceptionType.badCertificate);
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Secure connection could not be established.'));
    });

    test('unknown failure returns statusCode: 0, isSuccess: false with sensible message', () async {
      setupTransportError(DioExceptionType.unknown, customMessage: 'Socket closed unexpectedly');
      final response = await bolt.get('/test');

      expect(response.isSuccess, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.responseData, isNull);
      expect(response.message, equals('Socket closed unexpectedly'));
    });
  });

  group('DioBoltResponse unit tests', () {
    test('toString produces descriptive string', () {
      const response = DioBoltResponse(
        isSuccess: true,
        statusCode: 200,
        responseData: {'key': 'value'},
        message: 'OK',
      );

      expect(
        response.toString(),
        equals('DioBoltResponse(statusCode: 200, isSuccess: true, message: OK, responseData: {key: value})'),
      );
    });

    test('fromDioException handles badResponse with null statusMessage using default fallback', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 404,
          statusMessage: null,
          data: {'error': 'not found'},
        ),
        type: DioExceptionType.badResponse,
      );

      final boltResponse = DioBoltResponse.fromDioException(dioException);
      expect(boltResponse.isSuccess, isFalse);
      expect(boltResponse.statusCode, equals(404));
      expect(boltResponse.message, equals('Resource not found.'));
    });
  });
}