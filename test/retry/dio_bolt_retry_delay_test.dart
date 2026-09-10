import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:dio_bolt/src/retry/dio_bolt_retry_delay.dart';
import 'package:test/test.dart';

void main() {
  group('DioBoltRetryDelay - Tests', () {
    final calculator = DioBoltRetryDelay();

    test('calculates exponential backoff without jitter', () {
      const config = DioBoltRetryConfig(
        initialDelay: Duration(milliseconds: 100),
        backoffMultiplier: 2.0,
        maxDelay: Duration(seconds: 10),
        useJitter: false,
      );

      // attempt 1: 100 * (2^0) = 100ms
      expect(
        calculator.calculateDelay(attempt: 1, config: config),
        equals(const Duration(milliseconds: 100)),
      );
      // attempt 2: 100 * (2^1) = 200ms
      expect(
        calculator.calculateDelay(attempt: 2, config: config),
        equals(const Duration(milliseconds: 200)),
      );
      // attempt 3: 100 * (2^2) = 400ms
      expect(
        calculator.calculateDelay(attempt: 3, config: config),
        equals(const Duration(milliseconds: 400)),
      );
      // attempt 4: 100 * (2^3) = 800ms
      expect(
        calculator.calculateDelay(attempt: 4, config: config),
        equals(const Duration(milliseconds: 800)),
      );
    });

    test('clamps delay to maxDelay', () {
      const config = DioBoltRetryConfig(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 3.0,
        maxDelay: Duration(seconds: 2),
        useJitter: false,
      );

      // attempt 1: 1s
      expect(
        calculator.calculateDelay(attempt: 1, config: config),
        equals(const Duration(seconds: 1)),
      );
      // attempt 2: 3s -> clamped to 2s
      expect(
        calculator.calculateDelay(attempt: 2, config: config),
        equals(const Duration(seconds: 2)),
      );
      // attempt 3: 9s -> clamped to 2s
      expect(
        calculator.calculateDelay(attempt: 3, config: config),
        equals(const Duration(seconds: 2)),
      );
    });

    test('parses 429 Retry-After header with numeric delta-seconds', () {
      const config = DioBoltRetryConfig(
        maxDelay: Duration(seconds: 10),
        respectRetryAfter: true,
      );

      final error = DioException(
        requestOptions: RequestOptions(path: '/rate-limited'),
        response: Response(
          requestOptions: RequestOptions(path: '/rate-limited'),
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['3'],
          }),
        ),
      );

      final delay = calculator.calculateDelay(
        attempt: 1,
        config: config,
        error: error,
      );
      expect(delay, equals(const Duration(seconds: 3)));
    });

    test('parses 429 Retry-After header with HTTP-date', () {
      const config = DioBoltRetryConfig(
        maxDelay: Duration(seconds: 60),
        respectRetryAfter: true,
      );

      final targetTime = DateTime.now().add(const Duration(seconds: 5));
      final httpDateString = HttpDate.format(targetTime);

      final error = DioException(
        requestOptions: RequestOptions(path: '/rate-limited'),
        response: Response(
          requestOptions: RequestOptions(path: '/rate-limited'),
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': [httpDateString],
          }),
        ),
      );

      final delay = calculator.calculateDelay(
        attempt: 1,
        config: config,
        error: error,
      );
      // Allow slight timing difference of +/- 1 second
      expect(delay.inSeconds, inInclusiveRange(4, 6));
    });

    test(
      'clamps 429 Retry-After to maxDelay when clampRetryAfterToMaxDelay is true',
      () {
        const config = DioBoltRetryConfig(
          maxDelay: Duration(seconds: 2),
          respectRetryAfter: true,
          clampRetryAfterToMaxDelay: true,
        );

        final error = DioException(
          requestOptions: RequestOptions(path: '/rate-limited'),
          response: Response(
            requestOptions: RequestOptions(path: '/rate-limited'),
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': ['120'],
            }),
          ),
        );

        final delay = calculator.calculateDelay(
          attempt: 1,
          config: config,
          error: error,
        );
        expect(delay, equals(const Duration(seconds: 2)));
      },
    );

    test(
      'invalid 429 Retry-After header falls back to exponential backoff',
      () {
        const config = DioBoltRetryConfig(
          initialDelay: Duration(milliseconds: 300),
          useJitter: false,
        );

        final error = DioException(
          requestOptions: RequestOptions(path: '/rate-limited'),
          response: Response(
            requestOptions: RequestOptions(path: '/rate-limited'),
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': ['not-a-number-or-date'],
            }),
          ),
        );

        final delay = calculator.calculateDelay(
          attempt: 1,
          config: config,
          error: error,
        );
        expect(delay, equals(const Duration(milliseconds: 300)));
      },
    );

    test(
      '429 Retry-After date in the past falls back to exponential backoff',
      () {
        const config = DioBoltRetryConfig(
          initialDelay: Duration(milliseconds: 300),
          useJitter: false,
        );

        final pastDate = DateTime.now().subtract(const Duration(minutes: 5));
        final error = DioException(
          requestOptions: RequestOptions(path: '/rate-limited'),
          response: Response(
            requestOptions: RequestOptions(path: '/rate-limited'),
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': [HttpDate.format(pastDate)],
            }),
          ),
        );

        final delay = calculator.calculateDelay(
          attempt: 1,
          config: config,
          error: error,
        );
        expect(delay, equals(const Duration(milliseconds: 300)));
      },
    );

    test('custom delayCalculator takes precedence over 429 Retry-After', () {
      final config = DioBoltRetryConfig(
        delayCalculator: (attempt, initial, max, mult, jitter, err) =>
            Duration(milliseconds: attempt * 50),
      );

      final error = DioException(
        requestOptions: RequestOptions(path: '/rate-limited'),
        response: Response(
          requestOptions: RequestOptions(path: '/rate-limited'),
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['120'],
          }),
        ),
      );

      expect(
        calculator.calculateDelay(attempt: 1, config: config, error: error),
        equals(const Duration(milliseconds: 50)),
      );
      expect(
        calculator.calculateDelay(attempt: 2, config: config, error: error),
        equals(const Duration(milliseconds: 100)),
      );
    });
  });
}
