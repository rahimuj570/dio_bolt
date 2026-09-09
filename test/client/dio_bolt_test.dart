import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:test/test.dart';

class User {
  final int id;
  final String name;

  User({required this.id, required this.name});

  factory User.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return User(id: map['id'] as int, name: map['name'] as String);
  }
}

class UserPage {
  final List<User> users;
  final int page;
  final int total;

  UserPage({required this.users, required this.page, required this.total});

  factory UserPage.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    final userList = (map['data'] as List)
        .map((item) => User.fromJson(item))
        .toList();
    final pagination = map['pagination'] as Map<String, dynamic>;

    return UserPage(
      users: userList,
      page: pagination['page'] as int,
      total: pagination['total'] as int,
    );
  }
}

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

  group('DioBolt Raw API (DioBoltResponse)', () {
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

            if (options.cancelToken?.isCancelled ?? false) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                  error: 'Request cancelled',
                ),
              );
            }

            if (options.path == '/users/1' && options.method == 'GET') {
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

            if (options.path == '/paginated_users' && options.method == 'GET') {
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

            if (options.path == '/users' && options.method == 'POST') {
              options.onSendProgress?.call(50, 100);
              options.onReceiveProgress?.call(100, 100);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  statusMessage: 'Created',
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'PUT') {
              options.onSendProgress?.call(50, 100);
              options.onReceiveProgress?.call(100, 100);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'PATCH') {
              options.onSendProgress?.call(50, 100);
              options.onReceiveProgress?.call(100, 100);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  statusMessage: 'OK',
                  data: {'deleted': true},
                ),
              );
            }

            if (options.path == '/users/204' && options.method == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 204,
                  statusMessage: 'No Content',
                  data: null,
                ),
              );
            }

            if (options.path == '/error') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 500,
                    statusMessage: 'Internal Server Error',
                    data: {'error': 'Something failed'},
                  ),
                  type: DioExceptionType.badResponse,
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

    test('1. GET returns DioBoltResponse with complete response data', () async {
      final response = await bolt.get('/users/1');

      expect(response, isA<DioBoltResponse>());
      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.message, equals('OK'));
      expect(response.responseData, equals({'id': 1, 'name': 'Alice'}));
      expect(capturedOptions?.method, equals('GET'));
    });

    test('2. POST returns DioBoltResponse', () async {
      final response = await bolt.post(
        '/users',
        data: {'name': 'Charlie'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(201));
      expect(response.message, equals('Created'));
      expect(response.responseData, equals({'id': 3, 'name': 'Charlie'}));
      expect(capturedOptions?.method, equals('POST'));
    });

    test('3. PUT returns DioBoltResponse', () async {
      final response = await bolt.put(
        '/users/3',
        data: {'name': 'Charlie Updated'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'id': 3, 'name': 'Charlie Updated'}));
      expect(capturedOptions?.method, equals('PUT'));
    });

    test('4. PATCH returns DioBoltResponse', () async {
      final response = await bolt.patch(
        '/users/3',
        data: {'name': 'Charlie Patched'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'id': 3, 'name': 'Charlie Patched'}));
      expect(capturedOptions?.method, equals('PATCH'));
    });

    test('5. DELETE returns DioBoltResponse', () async {
      final response = await bolt.delete('/users/3');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.responseData, equals({'deleted': true}));
      expect(capturedOptions?.method, equals('DELETE'));
    });

    test('6-8. responseData preserves complete structure including pagination and nested fields', () async {
      final response = await bolt.get('/paginated_users');

      expect(response.isSuccess, isTrue);
      expect(response.responseData, isA<Map<String, dynamic>>());

      final map = response.responseData as Map<String, dynamic>;
      expect(map['success'], isTrue);
      expect(map['data'], isA<List>());
      expect((map['data'] as List), hasLength(2));
      expect(map['pagination']['page'], equals(1));
      expect(map['pagination']['total'], equals(100));
    });

    test('9. DELETE with 204 preserves statusCode and null responseData', () async {
      final response = await bolt.delete('/users/204');

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, equals(204));
      expect(response.responseData, isNull);
    });

    test('10. Query parameters reach Dio correctly', () async {
      await bolt.get(
        '/users/1',
        queryParameters: {'include': 'profile', 'limit': 10},
      );

      expect(capturedOptions?.queryParameters, equals({'include': 'profile', 'limit': 10}));
    });

    test('11. Header precedence: explicit headers override duplicate Options.headers', () async {
      final options = Options(headers: {
        'Authorization': 'Bearer old-token',
        'X-Keep': 'preserved',
      });

      await bolt.get(
        '/users/1',
        options: options,
        headers: {'Authorization': 'Bearer new-token'},
      );

      expect(capturedOptions?.headers['Authorization'], equals('Bearer new-token'));
      expect(capturedOptions?.headers['X-Keep'], equals('preserved'));
    });

    test('12. CancelToken is forwarded correctly', () async {
      final cancelToken = CancelToken();
      cancelToken.cancel('User aborted');

      expect(
        () => bolt.get('/users/1', cancelToken: cancelToken),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          equals(DioExceptionType.cancel),
        )),
      );
    });

    test('13. Send progress and receive progress are forwarded', () async {
      int? sendBytes;
      int? receiveBytes;

      await bolt.post(
        '/users',
        data: {'name': 'Charlie'},
        onSendProgress: (sent, total) => sendBytes = sent,
        onReceiveProgress: (received, total) => receiveBytes = received,
      );

      expect(sendBytes, equals(50));
      expect(receiveBytes, equals(100));
    });

    test('14. DioException propagates unchanged in Phase 2', () async {
      expect(
        () => bolt.get('/error'),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          equals(500),
        )),
      );
    });
  });

  group('DioBolt Typed Convenience API (getAs, postAs, etc.)', () {
    late Dio dio;
    late DioBolt bolt;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/users/1' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'id': 1, 'name': 'Alice'},
                ),
              );
            }

            if (options.path == '/paginated_users' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
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

            if (options.path == '/users' && options.method == 'POST') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'PUT') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'PATCH') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'id': 3, 'name': options.data['name']},
                ),
              );
            }

            if (options.path == '/users/3' && options.method == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'deleted': true},
                ),
              );
            }

            if (options.path == '/malformed' && options.method == 'GET') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: 'invalid json shape',
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

    test('1. getAs<User> decodes single entity', () async {
      final user = await bolt.getAs<User>(
        '/users/1',
        fromJson: User.fromJson,
      );

      expect(user, isA<User>());
      expect(user.id, equals(1));
      expect(user.name, equals('Alice'));
    });

    test('2. getAs<UserPage> decodes wrapped/paginated structure without automatic data reduction', () async {
      final page = await bolt.getAs<UserPage>(
        '/paginated_users',
        fromJson: UserPage.fromJson,
      );

      expect(page, isA<UserPage>());
      expect(page.users, hasLength(2));
      expect(page.users[0].name, equals('Alice'));
      expect(page.users[1].name, equals('Bob'));
      expect(page.page, equals(1));
      expect(page.total, equals(100));
    });

    test('3. postAs<User> sends body and decodes response', () async {
      final user = await bolt.postAs<User>(
        '/users',
        data: {'name': 'Charlie'},
        fromJson: User.fromJson,
      );

      expect(user.id, equals(3));
      expect(user.name, equals('Charlie'));
    });

    test('4. putAs<User> decodes response', () async {
      final user = await bolt.putAs<User>(
        '/users/3',
        data: {'name': 'Charlie Updated'},
        fromJson: User.fromJson,
      );

      expect(user.id, equals(3));
      expect(user.name, equals('Charlie Updated'));
    });

    test('5. patchAs<User> decodes response', () async {
      final user = await bolt.patchAs<User>(
        '/users/3',
        data: {'name': 'Charlie Patched'},
        fromJson: User.fromJson,
      );

      expect(user.id, equals(3));
      expect(user.name, equals('Charlie Patched'));
    });

    test('6. deleteAs<Map<String, dynamic>> decodes response', () async {
      final result = await bolt.deleteAs<Map<String, dynamic>>(
        '/users/3',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      expect(result['deleted'], isTrue);
    });

    test('7. fromJson exceptions propagate naturally when format is invalid', () async {
      expect(
        () => bolt.getAs<User>(
          '/malformed',
          fromJson: User.fromJson,
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });
}