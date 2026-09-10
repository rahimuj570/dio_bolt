import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../transfer/dio_bolt_file.dart';
import '../transfer/dio_bolt_transfer_utils.dart';
import 'dio_bolt_auth.dart';

/// Dedicated component responsible for request replayability checks,
/// retry [RequestOptions] construction, and retry execution.
class DioBoltRequestRetry {
  /// The Dio instance used to execute the retried request.
  final Dio dio;

  /// The authentication configuration providing header key and token builder.
  final DioBoltAuth auth;

  /// Creates a [DioBoltRequestRetry].
  DioBoltRequestRetry({required this.dio, required this.auth});

  /// Determines whether a request payload is safe to replay across retries.
  bool isReplayable(dynamic data, [RequestOptions? options]) {
    if (options != null) {
      final uploadFiles = options.extra[kDioBoltUploadFilesKey];
      if (uploadFiles is List<DioBoltFile>) {
        return DioBoltTransferUtils.areFilesReplayable(uploadFiles);
      }
    }
    if (data == null) return true;
    if (data is String || data is num || data is bool) {
      return true;
    }
    if (data is Map || data is List) {
      return true;
    }
    if (data is Uint8List || (data is List<int> && data is! Stream)) {
      return true;
    }
    // Generic arbitrary FormData is NOT assumed replayable
    if (data is FormData) {
      return false;
    }
    return false;
  }

  /// Constructs the retried [RequestOptions] with updated authorization header,
  /// cloned replayable body or fresh FormData, and retry marker.
  Future<RequestOptions> prepareRetryOptions(
    RequestOptions original,
    String newToken,
  ) async {
    final retryExtra = Map<String, dynamic>.from(original.extra);
    retryExtra[kDioBoltAuthRetriedKey] = true;

    final retryHeaders = Map<String, dynamic>.from(original.headers);

    // Remove any previous case-insensitive authorization header keys
    final existingKey = _findHeaderKey(retryHeaders, auth.headerKey);
    if (existingKey != null) {
      retryHeaders.remove(existingKey);
    }

    // Inject the new token
    final formattedToken = auth.tokenHeaderBuilder != null
        ? auth.tokenHeaderBuilder!(newToken)
        : 'Bearer $newToken';
    retryHeaders[auth.headerKey] = formattedToken;

    // Fresh FormData reconstruction if upload files are present
    dynamic retryData = original.data;
    final uploadFiles = original.extra[kDioBoltUploadFilesKey];
    if (uploadFiles is List<DioBoltFile>) {
      final uploadFields =
          original.extra[kDioBoltUploadFieldsKey] as Map<String, dynamic>?;
      retryData = await DioBoltTransferUtils.createFormData(
        files: uploadFiles,
        fields: uploadFields,
      );
    } else if (retryData is FormData) {
      retryData = retryData.clone();
    }

    return original.copyWith(
      headers: retryHeaders,
      extra: retryExtra,
      data: retryData,
    );
  }

  /// Executes the retried request via [dio.fetch].
  Future<Response<dynamic>> retry(
    RequestOptions original,
    String newToken,
  ) async {
    final retryOptions = await prepareRetryOptions(original, newToken);
    return dio.fetch<dynamic>(retryOptions);
  }

  /// Case-insensitively locates a header key in [headers].
  static String? _findHeaderKey(
    Map<String, dynamic> headers,
    String targetKey,
  ) {
    final lower = targetKey.toLowerCase();
    for (final key in headers.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }
}
