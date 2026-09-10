import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'dio_bolt_retry_config.dart';

/// Helper responsible for calculating backoff delays, handling Retry-After headers,
/// and applying jitter.
class DioBoltRetryDelay {
  final Random _random;

  /// Creates a [DioBoltRetryDelay].
  DioBoltRetryDelay([Random? random]) : _random = random ?? Random();

  /// Calculates the delay for the given [attempt] (1-indexed).
  Duration calculateDelay({
    required int attempt,
    required DioBoltRetryConfig config,
    DioException? error,
  }) {
    // 1. Check custom delay calculator if provided
    if (config.delayCalculator != null) {
      return config.delayCalculator!(
        attempt,
        config.initialDelay,
        config.maxDelay,
        config.backoffMultiplier,
        config.useJitter,
        error,
      );
    }

    // 2. Inspect 429 Retry-After header
    if (config.respectRetryAfter && error?.response?.statusCode == 429) {
      final retryAfterHeader = error?.response?.headers.value('retry-after');
      if (retryAfterHeader != null && retryAfterHeader.trim().isNotEmpty) {
        final serverDelay = _parseRetryAfter(retryAfterHeader.trim());
        if (serverDelay != null && serverDelay > Duration.zero) {
          if (config.clampRetryAfterToMaxDelay &&
              serverDelay > config.maxDelay) {
            return config.maxDelay;
          }
          return serverDelay;
        }
      }
    }

    // 3. Exponential backoff calculation: initialDelay * (multiplier ^ (attempt - 1))
    final multiplier = pow(config.backoffMultiplier, max(0, attempt - 1));
    final calculatedMs = (config.initialDelay.inMilliseconds * multiplier)
        .round();
    var delay = Duration(milliseconds: calculatedMs);

    // 4. Clamp to maxDelay
    if (delay > config.maxDelay) {
      delay = config.maxDelay;
    }

    // 5. Apply jitter if enabled (adds 0% - 20% random variance, capped at maxDelay)
    if (config.useJitter && delay > Duration.zero) {
      final jitterFactor = _random.nextDouble() * 0.2; // 0.0 to 0.2
      final jitterMs = (delay.inMilliseconds * jitterFactor).round();
      final jitteredMs = delay.inMilliseconds + jitterMs;
      delay = Duration(milliseconds: jitteredMs);
      if (delay > config.maxDelay) {
        delay = config.maxDelay;
      }
    }

    return delay;
  }

  /// Parses a `Retry-After` header value into a [Duration].
  ///
  /// Supports:
  /// - Delta-seconds (e.g. `120` -> 120 seconds).
  /// - HTTP-date (e.g. `Wed, 21 Oct 2026 07:28:00 GMT`).
  Duration? _parseRetryAfter(String value) {
    // 1. Try numeric seconds
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return Duration(seconds: seconds);
    }

    // 2. Try HTTP-date
    try {
      final httpDate = HttpDate.parse(value);
      final difference = httpDate.difference(DateTime.now());
      return difference.isNegative ? Duration.zero : difference;
    } catch (_) {
      // 3. Fallback to ISO 8601 string if applicable
      final isoDate = DateTime.tryParse(value);
      if (isoDate != null) {
        final difference = isoDate.difference(DateTime.now());
        return difference.isNegative ? Duration.zero : difference;
      }
    }

    return null;
  }
}
