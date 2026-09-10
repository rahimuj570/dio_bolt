import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:dio_bolt/src/auth/dio_bolt_request_retry.dart';
import 'package:test/test.dart';

void main() {
  group('DioBoltRequestRetry - Unit Tests', () {
    late Dio dio;
    late DioBoltAuth auth;
    late DioBoltRequestRetry retryHandler;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      auth = DioBoltAuth(
        getAccessToken: () => 'token',
        refreshToken: (_) => 'new-token',
        headerKey: 'Authorization',
      );
      retryHandler = DioBoltRequestRetry(dio: dio, auth: auth);
    });

    test('isReplayable correctly identifies safe and unsafe payloads', () {
      // Safe payloads
      expect(retryHandler.isReplayable(null), isTrue);
      expect(retryHandler.isReplayable({'key': 'value'}), isTrue);
      expect(retryHandler.isReplayable([1, 2, 3]), isTrue);
      expect(retryHandler.isReplayable('string-payload'), isTrue);
      expect(retryHandler.isReplayable(42), isTrue);
      expect(retryHandler.isReplayable(true), isTrue);
      expect(retryHandler.isReplayable(Uint8List.fromList([1, 2, 3])), isTrue);
      expect(retryHandler.isReplayable([1, 2, 3]), isTrue);
      expect(retryHandler.isReplayable(FormData.fromMap({'a': 'b'})), isTrue);

      // Unsafe payload: Stream
      expect(retryHandler.isReplayable(Stream<List<int>>.empty()), isFalse);

      // Unsafe payload: Unknown custom object
      expect(retryHandler.isReplayable(Object()), isFalse);
    });

    test('prepareRetryOptions sets retry marker, replaces authorization header, and clones FormData', () {
      final originalFormData = FormData.fromMap({'field': 'val'});
      final original = RequestOptions(
        path: '/items',
        headers: {
          'Authorization': 'Bearer old-token',
          'X-Custom': '123',
        },
        extra: {'existingExtra': true},
        queryParameters: {'q': 'dart'},
        contentType: 'application/json',
        data: originalFormData,
      );

      final prepared = retryHandler.prepareRetryOptions(original, 'new-token-abc');

      // 1. Retry marker applied
      expect(prepared.extra[kDioBoltAuthRetriedKey], isTrue);
      expect(prepared.extra['existingExtra'], isTrue);

      // 2. Authorization updated to new token
      expect(prepared.headers['Authorization'], equals('Bearer new-token-abc'));
      expect(prepared.headers['X-Custom'], equals('123'));

      // 3. Options preserved
      expect(prepared.queryParameters, equals({'q': 'dart'}));
      expect(prepared.contentType, equals('application/json'));

      // 4. FormData cloned (different instance)
      expect(prepared.data, isA<FormData>());
      expect(prepared.data, isNot(same(originalFormData)));
    });

    test('prepareRetryOptions respects custom headerKey and tokenHeaderBuilder', () {
      final customAuth = DioBoltAuth(
        getAccessToken: () => 't',
        refreshToken: (_) => 't',
        headerKey: 'X-API-KEY',
        tokenHeaderBuilder: (token) => 'Custom $token',
      );
      final customRetry = DioBoltRequestRetry(dio: dio, auth: customAuth);

      final original = RequestOptions(
        path: '/test',
        headers: {'X-API-KEY': 'old-key'},
      );

      final prepared = customRetry.prepareRetryOptions(original, 'secret-123');

      expect(prepared.headers['X-API-KEY'], equals('Custom secret-123'));
    });
  });
}
