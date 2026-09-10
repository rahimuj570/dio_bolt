import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'dio_bolt_auth.dart';

/// Dedicated component responsible for request replayability checks,
/// retry [RequestOptions] construction, and retry execution.
class DioBoltRequestRetry {
  /// The Dio instance used to execute the retried request.
  final Dio dio;

  /// The authentication configuration providing header key and token builder.
  final DioBoltAuth auth;

  /// Creates a [DioBoltRequestRetry].
  DioBoltRequestRetry({
    required this.dio,
    required this.auth,
  });

  /// Determines whether a request payload is safe to replay across retries.
  ///
  /// Conservative safety guarantees:
  /// - `null`, primitives (String, num, bool), and Map/List collections are safe.
  /// - `Uint8List` and in-memory byte buffers are safe.
  /// - `FormData` is safe via deep cloning.
  /// - One-shot streaming payloads (`Stream<List<int>>`) are NOT replayable.
  bool isReplayable(dynamic data) {
    if (data == null) return true;
    if (data is Map || data is List || data is String || data is num || data is bool) {
      return true;
    }
    if (data is Uint8List || (data is List<int> && data is! Stream)) {
      return true;
    }
    if (data is FormData) {
      return true;
    }
    if (data is Stream) {
      return false;
    }
    return true;
  }

  /// Constructs the retried [RequestOptions] with updated authorization header,
  /// cloned replayable body, and retry marker.
  RequestOptions prepareRetryOptions(RequestOptions original, String newToken) {
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

    // Clone FormData if applicable
    dynamic retryData = original.data;
    if (retryData is FormData) {
      retryData = retryData.clone();
    }

    return original.copyWith(
      headers: retryHeaders,
      extra: retryExtra,
      data: retryData,
    );
  }

  /// Executes the retried request via [dio.fetch].
  Future<Response<dynamic>> retry(RequestOptions original, String newToken) {
    final retryOptions = prepareRetryOptions(original, newToken);
    return dio.fetch<dynamic>(retryOptions);
  }

  /// Case-insensitively locates a header key in [headers].
  static String? _findHeaderKey(Map<String, dynamic> headers, String targetKey) {
    final lower = targetKey.toLowerCase();
    for (final key in headers.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }
}
