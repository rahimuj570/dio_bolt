import 'package:dio/dio.dart';
import '../auth/dio_bolt_auth.dart';
import '../auth/dio_bolt_auth_interceptor.dart';
import '../auth/dio_bolt_refresh_manager.dart';
import '../auth/dio_bolt_request_retry.dart';
import '../logging/dio_bolt_log_config.dart';
import '../logging/dio_bolt_logging_interceptor.dart';
import '../model/dio_bolt_response.dart';
import '../retry/dio_bolt_retry_config.dart';
import '../retry/dio_bolt_retry_interceptor.dart';
import '../retry/dio_bolt_retry_policy.dart';

/// A lightweight production networking layer built on top of [Dio].
///
/// Dio Bolt removes repetitive networking boilerplate and provides a universal
/// non-throwing response envelope [DioBoltResponse] for all outcomes (2xx, 4xx, 5xx,
/// timeouts, network errors, and cancellations), while keeping the underlying
/// [Dio] instance fully accessible via [dio].
class DioBolt {
  /// The underlying [Dio] client instance.
  final Dio dio;

  /// Creates a new [DioBolt] instance.
  ///
  /// Optionally accepts an existing [dio] instance, custom [BaseOptions],
  /// authentication configuration [auth], retry configuration [retryConfig],
  /// or logging configuration ([enableLogging] and [logConfig]).
  DioBolt({
    Dio? dio,
    BaseOptions? options,
    DioBoltAuth? auth,
    DioBoltRetryConfig? retryConfig,
    bool enableLogging = false,
    DioBoltLogConfig? logConfig,
  }) : dio = dio ?? Dio(options) {
    final effectiveLogConfig = logConfig ??
        (enableLogging ? const DioBoltLogConfig(enabled: true) : null);

    DioBoltLoggingInterceptor? loggingInterceptor;
    if (effectiveLogConfig != null && effectiveLogConfig.enabled) {
      loggingInterceptor =
          DioBoltLoggingInterceptor(config: effectiveLogConfig);
    }

    // 1. Attach Authentication Interceptor (Index 0) if auth is provided
    if (auth != null) {
      final refreshManager = DioBoltRefreshManager.fromDio(
        auth: auth,
        mainDio: this.dio,
        logConfig: effectiveLogConfig,
      );
      final retryHandler = DioBoltRequestRetry(
        dio: this.dio,
        auth: auth,
      );
      this.dio.interceptors.add(
            DioBoltAuthInterceptor(
              refreshManager: refreshManager,
              retryHandler: retryHandler,
            ),
          );
    }

    // 2. Attach Retry Interceptor (Index 1) if retryConfig is provided
    if (retryConfig != null) {
      final policy = DioBoltRetryPolicy(config: retryConfig);
      this.dio.interceptors.add(
            DioBoltRetryInterceptor(
              policy: policy,
              dio: this.dio,
              onRetryLog: loggingInterceptor != null
                  ? (opt, reason, delay, attempt) =>
                      loggingInterceptor!.logRetry(
                        options: opt,
                        reason: reason,
                        delay: delay,
                        attempt: attempt,
                      )
                  : null,
            ),
          );
    }

    // 3. Attach Logging Interceptor (Index 2) if logging is enabled
    if (loggingInterceptor != null) {
      this.dio.interceptors.add(loggingInterceptor);
    }
  }

  // ===========================================================================
  // Raw API (Universal non-throwing DioBoltResponse)
  // ===========================================================================

  /// Performs an HTTP GET request and returns a [DioBoltResponse].
  ///
  /// The complete raw response body is preserved in [DioBoltResponse.responseData].
  /// When [headers] is passed, it is merged with [options.headers], with
  /// explicit [headers] taking precedence over duplicate keys in [options.headers].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: _mergeOptions(options, headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    }
  }

  /// Performs an HTTP POST request and returns a [DioBoltResponse].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.post<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, headers),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    }
  }

  /// Performs an HTTP PUT request and returns a [DioBoltResponse].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.put<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, headers),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    }
  }

  /// Performs an HTTP PATCH request and returns a [DioBoltResponse].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.patch<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, headers),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    }
  }

  /// Performs an HTTP DELETE request and returns a [DioBoltResponse].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.delete<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, headers),
        cancelToken: cancelToken,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Merges explicit [headers] with [options.headers].
  ///
  /// Explicit [headers] will overwrite duplicate keys present in [options.headers].
  Options _mergeOptions(Options? options, Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) {
      return options ?? Options();
    }

    final merged = options?.headers != null
        ? Map<String, dynamic>.from(options!.headers!)
        : <String, dynamic>{};
    merged.addAll(headers);

    if (options != null) {
      return options.copyWith(headers: merged);
    }
    return Options(headers: merged);
  }
}