import 'package:dio/dio.dart';
import '../model/dio_bolt_response.dart';

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
  /// Optionally accepts an existing [dio] instance or custom [BaseOptions].
  DioBolt({Dio? dio, BaseOptions? options}) : dio = dio ?? Dio(options);

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