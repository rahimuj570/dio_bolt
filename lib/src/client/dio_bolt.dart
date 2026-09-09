import 'package:dio/dio.dart';
import '../model/dio_bolt_response.dart';

/// A lightweight production networking layer built on top of [Dio].
///
/// Dio Bolt removes repetitive networking boilerplate while keeping
/// the underlying [Dio] instance fully accessible via [dio].
class DioBolt {
  /// The underlying [Dio] client instance.
  final Dio dio;

  /// Creates a new [DioBolt] instance.
  ///
  /// Optionally accepts an existing [dio] instance or custom [BaseOptions].
  DioBolt({Dio? dio, BaseOptions? options}) : dio = dio ?? Dio(options);

  // ===========================================================================
  // 1. Raw / Flexible API (returns DioBoltResponse preserving complete response)
  // ===========================================================================

  /// Performs an HTTP GET request and returns a [DioBoltResponse].
  ///
  /// The complete raw response body is preserved in [DioBoltResponse.responseData].
  /// When [headers] is passed, it is merged with [options.headers], with
  /// explicit [headers] taking precedence over duplicate keys in [options.headers].
  Future<DioBoltResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final response = await dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: _mergeOptions(options, headers),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );

    return _toBoltResponse(response);
  }

  /// Performs an HTTP POST request and returns a [DioBoltResponse].
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
    final response = await dio.post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _mergeOptions(options, headers),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _toBoltResponse(response);
  }

  /// Performs an HTTP PUT request and returns a [DioBoltResponse].
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
    final response = await dio.put<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _mergeOptions(options, headers),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _toBoltResponse(response);
  }

  /// Performs an HTTP PATCH request and returns a [DioBoltResponse].
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
    final response = await dio.patch<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _mergeOptions(options, headers),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _toBoltResponse(response);
  }

  /// Performs an HTTP DELETE request and returns a [DioBoltResponse].
  Future<DioBoltResponse> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final response = await dio.delete<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _mergeOptions(options, headers),
      cancelToken: cancelToken,
    );

    return _toBoltResponse(response);
  }

  // ===========================================================================
  // 2. Typed Convenience API (explicit JSON/model decoding via fromJson)
  // ===========================================================================

  /// Performs an HTTP GET request and converts the response body using [fromJson].
  ///
  /// The [fromJson] callback receives the complete `response.data`.
  Future<T> getAs<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final boltResponse = await get(
      path,
      queryParameters: queryParameters,
      headers: headers,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );

    return fromJson(boltResponse.responseData);
  }

  /// Performs an HTTP POST request and converts the response body using [fromJson].
  Future<T> postAs<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final boltResponse = await post(
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return fromJson(boltResponse.responseData);
  }

  /// Performs an HTTP PUT request and converts the response body using [fromJson].
  Future<T> putAs<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final boltResponse = await put(
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return fromJson(boltResponse.responseData);
  }

  /// Performs an HTTP PATCH request and converts the response body using [fromJson].
  Future<T> patchAs<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final boltResponse = await patch(
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return fromJson(boltResponse.responseData);
  }

  /// Performs an HTTP DELETE request and converts the response body using [fromJson].
  Future<T> deleteAs<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final boltResponse = await delete(
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      options: options,
      cancelToken: cancelToken,
    );

    return fromJson(boltResponse.responseData);
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

  /// Converts a Dio [Response] into a normalized [DioBoltResponse].
  DioBoltResponse _toBoltResponse(Response response) {
    final statusCode = response.statusCode ?? 0;
    final isSuccess = statusCode >= 200 && statusCode < 300;

    return DioBoltResponse(
      isSuccess: isSuccess,
      statusCode: statusCode,
      responseData: response.data,
      message: response.statusMessage,
    );
  }
}