import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:dio_bolt/src/retry/dio_bolt_retry_policy.dart';
import 'package:test/test.dart';

void main() {
  group('DioBoltRetryPolicy - Tests', () {
    const policy = DioBoltRetryPolicy(config: DioBoltRetryConfig());

    DioException makeHttpError(int statusCode, {String method = 'GET', dynamic data, Map<String, dynamic>? extra}) {
      final req = RequestOptions(path: '/test', method: method, data: data, extra: extra);
      return DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: statusCode),
        type: DioExceptionType.badResponse,
      );
    }

    DioException makeTransportError(DioExceptionType type, {String method = 'GET', dynamic data, Map<String, dynamic>? extra}) {
      final req = RequestOptions(path: '/test', method: method, data: data, extra: extra);
      return DioException(
        requestOptions: req,
        type: type,
      );
    }

    test('1. Retries default eligible status codes: 408, 429, 500, 502, 503, 504', () async {
      for (final code in [408, 429, 500, 502, 503, 504]) {
        final err = makeHttpError(code);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isTrue, reason: 'Status $code should be retryable');
      }
    });

    test('2. Does NOT retry non-eligible status codes: 400, 401, 403, 404, 405, 409, 422', () async {
      for (final code in [400, 401, 403, 404, 405, 409, 422]) {
        final err = makeHttpError(code);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isFalse, reason: 'Status $code must NOT be retryable');
      }
    });

    test('3. Retries eligible transport errors: timeout, connectionError', () async {
      final eligibleTypes = [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ];
      for (final type in eligibleTypes) {
        final err = makeTransportError(type);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isTrue, reason: 'Transport error $type should be retryable');
      }
    });

    test('4. Does NOT retry non-eligible transport errors: badCertificate, cancel', () async {
      final ineligibleTypes = [
        DioExceptionType.badCertificate,
        DioExceptionType.cancel,
      ];
      for (final type in ineligibleTypes) {
        final err = makeTransportError(type);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isFalse, reason: 'Transport error $type must NOT be retryable');
      }
    });

    test('5. Method safety: GET, HEAD, OPTIONS, PUT, DELETE retry by default; POST, PATCH rejected', () async {
      for (final method in ['GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE']) {
        final err = makeHttpError(503, method: method);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isTrue, reason: 'Method $method should be retryable by default');
      }

      for (final method in ['POST', 'PATCH']) {
        final err = makeHttpError(503, method: method);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isFalse, reason: 'Method $method must NOT be retryable by default');
      }
    });

    test('6. Per-request override: copyWithRetry(enabled: true) permits POST retry', () async {
      final options = Options().copyWithRetry(enabled: true);
      final err = makeHttpError(503, method: 'POST', extra: options.extra);
      final should = await policy.shouldRetry(err, err.requestOptions, 0);
      expect(should, isTrue);
    });

    test('7. Per-request override: copyWithRetry(enabled: false) disables GET retry', () async {
      final options = Options().copyWithRetry(enabled: false);
      final err = makeHttpError(503, method: 'GET', extra: options.extra);
      final should = await policy.shouldRetry(err, err.requestOptions, 0);
      expect(should, isFalse);
    });

    test('8. Body replayability: Safe bodies allow retry', () async {
      final safeBodies = [
        null,
        'string body',
        123,
        true,
        {'json': 'key'},
        ['item1', 'item2'],
        Uint8List.fromList([1, 2, 3]),
        [1, 2, 3],
        FormData.fromMap({'field': 'value'}),
        FormData.fromMap({
          'file': MultipartFile.fromBytes([1, 2, 3], filename: 'test.bin'),
        }),
      ];

      for (final body in safeBodies) {
        final err = makeHttpError(503, data: body);
        final should = await policy.shouldRetry(err, err.requestOptions, 0);
        expect(should, isTrue, reason: 'Body ${body.runtimeType} should be replayable');
      }
    });

    test('9. Body replayability: Unsafe one-shot streams and finalized files REJECT retry even with override', () async {
      final streamBody = Stream<List<int>>.value([1, 2, 3]);
      final overrideExtra = Options().copyWithRetry(enabled: true).extra;

      final err = makeHttpError(503, data: streamBody, extra: overrideExtra);
      final should = await policy.shouldRetry(err, err.requestOptions, 0);
      expect(should, isFalse, reason: 'One-shot stream must NOT be retried even with explicit override');
    });

    test('10. Body replayability: Unknown/custom body types REJECT retry even with override', () async {
      final customObject = _UnknownCustomPayload('some data');
      final overrideExtra = Options().copyWithRetry(enabled: true).extra;

      final err = makeHttpError(503, data: customObject, extra: overrideExtra);
      final should = await policy.shouldRetry(err, err.requestOptions, 0);
      expect(should, isFalse, reason: 'Unknown custom object must NOT be retried even with explicit override');
    });

    test('11. Max retries limit enforcement', () async {
      final err = makeHttpError(503);
      // default maxRetries is 3
      expect(await policy.shouldRetry(err, err.requestOptions, 0), isTrue); // attempt 0 -> retry 1
      expect(await policy.shouldRetry(err, err.requestOptions, 1), isTrue); // attempt 1 -> retry 2
      expect(await policy.shouldRetry(err, err.requestOptions, 2), isTrue); // attempt 2 -> retry 3
      expect(await policy.shouldRetry(err, err.requestOptions, 3), isFalse); // attempt 3 -> max reached!
    });

    test('12. Custom retryEvaluator with (error, options, attempt)', () async {
      final customPolicy = DioBoltRetryPolicy(
        config: DioBoltRetryConfig(
          retryEvaluator: (error, options, attempt) {
            // Only retry if header 'X-Retry-Allowed' is true
            return options.headers['X-Retry-Allowed'] == 'true';
          },
        ),
      );

      final reqAllowed = RequestOptions(path: '/test', headers: {'X-Retry-Allowed': 'true'});
      final errAllowed = DioException(requestOptions: reqAllowed, response: Response(requestOptions: reqAllowed, statusCode: 500));
      expect(await customPolicy.shouldRetry(errAllowed, reqAllowed, 0), isTrue);

      final reqDenied = RequestOptions(path: '/test', headers: {'X-Retry-Allowed': 'false'});
      final errDenied = DioException(requestOptions: reqDenied, response: Response(requestOptions: reqDenied, statusCode: 500));
      expect(await customPolicy.shouldRetry(errDenied, reqDenied, 0), isFalse);
    });
  });
}

class _UnknownCustomPayload {
  final String value;
  _UnknownCustomPayload(this.value);
}
