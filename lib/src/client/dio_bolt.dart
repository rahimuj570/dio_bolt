import 'dart:io';
import 'dart:typed_data';
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
import '../transfer/dio_bolt_file.dart';
import '../transfer/dio_bolt_transfer_utils.dart';

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
    final effectiveLogConfig =
        logConfig ??
        (enableLogging ? const DioBoltLogConfig(enabled: true) : null);

    DioBoltLoggingInterceptor? loggingInterceptor;
    if (effectiveLogConfig != null && effectiveLogConfig.enabled) {
      loggingInterceptor = DioBoltLoggingInterceptor(
        config: effectiveLogConfig,
      );
    }

    // 1. Attach Authentication Interceptor (Index 0) if auth is provided
    if (auth != null) {
      final refreshManager = DioBoltRefreshManager.fromDio(
        auth: auth,
        mainDio: this.dio,
        logConfig: effectiveLogConfig,
      );
      final retryHandler = DioBoltRequestRetry(dio: this.dio, auth: auth);
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
              ? (opt, reason, delay, attempt) => loggingInterceptor!.logRetry(
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
  /// When [headers] is passed, it is merged with [Options.headers], with
  /// explicit [headers] taking precedence over duplicate keys in [Options.headers].
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

  /// Performs a multipart file upload request and returns a [DioBoltResponse].
  ///
  /// Supports single [file] or multiple [files], along with metadata [data] fields.
  /// Reconstructs fresh multipart streams on retries to ensure complete byte transmission.
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> upload(
    String path, {
    DioBoltFile? file,
    List<DioBoltFile>? files,
    Map<String, dynamic>? data,
    String method = 'POST',
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final uploadFileList = <DioBoltFile>[?file, ...?files];

      final formData = await DioBoltTransferUtils.createFormData(
        files: uploadFileList,
        fields: data,
      );

      final mergedOptions = _mergeOptions(
        options,
        headers,
      ).copyWith(method: method);

      // Attach file descriptors to extra for fresh retry reconstruction
      final effectiveExtra = Map<String, dynamic>.from(
        mergedOptions.extra ?? {},
      );
      effectiveExtra[kDioBoltUploadFilesKey] = uploadFileList;
      if (data != null) {
        effectiveExtra[kDioBoltUploadFieldsKey] = data;
      }
      final requestOptions = mergedOptions.copyWith(extra: effectiveExtra);

      final response = await dio.request<dynamic>(
        path,
        data: formData,
        queryParameters: queryParameters,
        options: requestOptions,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

      return DioBoltResponse.fromResponse(response);
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    } catch (e) {
      return DioBoltResponse(
        isSuccess: false,
        statusCode: 0,
        responseData: null,
        message: e.toString(),
      );
    }
  }

  /// Downloads a remote file to [savePath] on local disk and returns a [DioBoltResponse].
  ///
  /// Uses an atomic temporary file strategy (`.tmp` file during transfer, atomically moved
  /// to [savePath] upon 100% successful completion).
  ///
  /// If [overwrite] is `false` and [savePath] already exists, immediately returns a conflict
  /// response before any network request is dispatched.
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> download(
    String urlPath, {
    required String savePath,
    bool overwrite = true,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final destFile = File(savePath);

    // 1. Pre-flight check: overwrite=false and destination already exists
    if (!overwrite && destFile.existsSync()) {
      return DioBoltResponse(
        isSuccess: false,
        statusCode: 0,
        responseData: null,
        message:
            'File already exists at "$savePath" and overwrite is disabled.',
      );
    }

    // 2. Ensure parent directory exists before creating temporary download file
    final parentDir = destFile.parent;
    if (!await parentDir.exists()) {
      try {
        await parentDir.create(recursive: true);
      } catch (e) {
        return DioBoltResponse(
          isSuccess: false,
          statusCode: 0,
          responseData: null,
          message: 'Failed to create parent directory for "$savePath": $e',
        );
      }
    }

    final tempPath = DioBoltTransferUtils.generateTempFilePath(savePath);

    try {
      final mergedOptions = _mergeOptions(options, headers);

      final response = await dio.download(
        urlPath,
        tempPath,
        queryParameters: queryParameters,
        options: mergedOptions,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        deleteOnError: true,
      );

      // 3. Commit temporary file atomically to final destination
      await DioBoltTransferUtils.commitTempFile(
        tempPath: tempPath,
        destinationPath: savePath,
        overwrite: overwrite,
      );

      return DioBoltResponse(
        isSuccess: true,
        statusCode: response.statusCode ?? 200,
        responseData: savePath,
        message: response.statusMessage ?? 'OK',
      );
    } on DioException catch (e) {
      await DioBoltTransferUtils.cleanTempFile(tempPath);
      return DioBoltResponse.fromDioException(e);
    } catch (e) {
      await DioBoltTransferUtils.cleanTempFile(tempPath);
      return DioBoltResponse(
        isSuccess: false,
        statusCode: 0,
        responseData: null,
        message: e.toString(),
      );
    }
  }

  /// Downloads binary content directly into memory and returns a [DioBoltResponse]
  /// with a [Uint8List] payload in [DioBoltResponse.responseData].
  ///
  /// Always returns a [DioBoltResponse]; never throws for normal HTTP or network failures.
  Future<DioBoltResponse> downloadBytes(
    String urlPath, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final mergedOptions = _mergeOptions(
        options,
        headers,
      ).copyWith(responseType: ResponseType.bytes);

      final response = await dio.get<dynamic>(
        urlPath,
        queryParameters: queryParameters,
        options: mergedOptions,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

      final rawData = response.data;
      Uint8List? bytesData;
      if (rawData is Uint8List) {
        bytesData = rawData;
      } else if (rawData is List<int>) {
        bytesData = Uint8List.fromList(rawData);
      } else if (rawData is List) {
        bytesData = Uint8List.fromList(List<int>.from(rawData));
      }

      final isSuccess =
          (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300;

      return DioBoltResponse(
        isSuccess: isSuccess,
        statusCode: response.statusCode ?? 200,
        responseData: bytesData ?? rawData,
        message: response.statusMessage ?? 'OK',
      );
    } on DioException catch (e) {
      return DioBoltResponse.fromDioException(e);
    } catch (e) {
      return DioBoltResponse(
        isSuccess: false,
        statusCode: 0,
        responseData: null,
        message: e.toString(),
      );
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Merges explicit [headers] with [Options.headers].
  ///
  /// Explicit [headers] will overwrite duplicate keys present in [Options.headers].
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
