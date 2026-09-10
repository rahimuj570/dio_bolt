import 'dart:async';
import 'package:dio/dio.dart';

export 'dio_bolt_retry_options.dart';

/// Custom evaluation callback to dynamically determine whether a failed request should be retried.
///
/// Invoked after basic safety validations (e.g. body replayability).
/// Return `true` to allow retry, or `false` to abort retry.
typedef RetryEvaluator = FutureOr<bool> Function(
  DioException error,
  RequestOptions options,
  int attempt,
);

/// Custom delay calculation function.
///
/// When provided, this calculator takes full precedence over default delay computation,
/// including 429 `Retry-After` parsing and exponential backoff curves.
/// Useful for injecting deterministic delays in tests or implementing custom backoff curves.
typedef RetryDelayCalculator = Duration Function(
  int attempt,
  Duration initialDelay,
  Duration maxDelay,
  double backoffMultiplier,
  bool useJitter,
  DioException? error,
);

/// Public configuration for automatic network and server failure retries.
class DioBoltRetryConfig {
  /// Maximum number of retry attempts before giving up.
  ///
  /// For example, `maxRetries: 3` means 1 original attempt + up to 3 retries (max 4 total attempts).
  /// Defaults to `3`.
  final int maxRetries;

  /// Initial base delay before the first retry attempt.
  ///
  /// Defaults to `500` milliseconds.
  final Duration initialDelay;

  /// Maximum ceiling delay for any single retry attempt.
  ///
  /// Defaults to `5` seconds.
  final Duration maxDelay;

  /// Multiplier applied to the delay on each subsequent retry.
  ///
  /// Defaults to `2.0` (exponential backoff).
  final double backoffMultiplier;

  /// Whether to add a random jitter to the calculated delay to prevent thundering herd storms.
  ///
  /// Defaults to `true`.
  final bool useJitter;

  /// Set of HTTP status codes eligible for automatic retry.
  ///
  /// Defaults to `{408, 429, 500, 502, 503, 504}`.
  final Set<int> retryableStatusCodes;

  /// Set of [DioExceptionType] transport errors eligible for automatic retry.
  ///
  /// Defaults to `{connectionTimeout, sendTimeout, receiveTimeout, connectionError}`.
  final Set<DioExceptionType> retryableDioErrors;

  /// Set of HTTP methods eligible for automatic retry.
  ///
  /// Defaults to `{'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'}`.
  /// Note: `POST` and `PATCH` are excluded by default for idempotency safety.
  final Set<String> retryableMethods;

  /// Optional custom evaluator to dynamically permit or reject retry attempts.
  final RetryEvaluator? retryEvaluator;

  /// Optional custom delay calculator.
  final RetryDelayCalculator? delayCalculator;

  /// Whether to parse and respect the server's `Retry-After` response header on HTTP 429.
  ///
  /// Defaults to `true`.
  final bool respectRetryAfter;

  /// Whether server-provided `Retry-After` duration is clamped to [maxDelay].
  ///
  /// Defaults to `true`.
  final bool clampRetryAfterToMaxDelay;

  /// Creates a [DioBoltRetryConfig].
  const DioBoltRetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 5),
    this.backoffMultiplier = 2.0,
    this.useJitter = true,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.retryableDioErrors = const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    },
    this.retryableMethods = const {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'},
    this.retryEvaluator,
    this.delayCalculator,
    this.respectRetryAfter = true,
    this.clampRetryAfterToMaxDelay = true,
  });
}
