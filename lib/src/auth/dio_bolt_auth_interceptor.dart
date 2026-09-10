import 'package:dio/dio.dart';
import '../model/dio_bolt_response.dart';
import 'dio_bolt_auth_options.dart';
import 'dio_bolt_refresh_manager.dart';
import 'dio_bolt_request_retry.dart';

/// Interceptor integrating authentication into Dio's interceptor lifecycle.
///
/// Delegates refresh coordination to [DioBoltRefreshManager] and retry
/// execution to [DioBoltRequestRetry].
class DioBoltAuthInterceptor extends Interceptor {
  /// The manager coordinating single-flight token refresh.
  final DioBoltRefreshManager refreshManager;

  /// The component handling request replayability and retry execution.
  final DioBoltRequestRetry retryHandler;

  /// Creates a [DioBoltAuthInterceptor].
  DioBoltAuthInterceptor({
    required this.refreshManager,
    required this.retryHandler,
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. If skipAuth is requested for this request, bypass token injection
    if (options.extra[kDioBoltSkipAuthKey] == true) {
      return handler.next(options);
    }

    // 2. Case-insensitive check for existing explicit Authorization header
    final explicitKey = _findHeaderKey(options.headers, refreshManager.auth.headerKey);
    if (explicitKey != null) {
      // Explicit header supplied by caller; preserve it without overwriting
      return handler.next(options);
    }

    // 3. Obtain token from provider
    try {
      final token = await refreshManager.auth.getAccessToken();
      if (token != null && token.isNotEmpty) {
        final formattedToken = refreshManager.auth.tokenHeaderBuilder != null
            ? refreshManager.auth.tokenHeaderBuilder!(token)
            : 'Bearer $token';
        options.headers[refreshManager.auth.headerKey] = formattedToken;
      }
    } catch (_) {
      // Callback exceptions must not break request dispatching
    }

    return handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;

    // 1. Only HTTP 401 Unauthorized triggers automatic refresh
    if (response?.statusCode != 401) {
      return handler.next(err);
    }

    // 2. Check if request opted out of authentication/refresh
    if (options.extra[kDioBoltSkipAuthKey] == true) {
      return handler.next(err);
    }

    // 3. Retry-once protection: prevent infinite loops
    if (options.extra[kDioBoltAuthRetriedKey] == true) {
      return handler.next(err);
    }

    // 4. Check payload replayability via retry component
    if (!retryHandler.isReplayable(options.data)) {
      return handler.next(err);
    }

    // 5. Attempt token refresh (delegated to DioBoltRefreshManager)
    final initiating401Response = DioBoltResponse.fromDioException(err);
    final String? newToken;

    try {
      newToken = await refreshManager.waitForTokenOrCancel(
        initiating401Response,
        options.cancelToken,
      );
    } on DioException catch (cancelErr) {
      // Cancelled while waiting for refresh
      return handler.next(cancelErr);
    } catch (_) {
      return handler.next(err);
    }

    // If refresh failed, return the original 401 error
    if (newToken == null || newToken.isEmpty) {
      return handler.next(err);
    }

    // 6. Execute retry via retry component
    try {
      final retriedResponse = await retryHandler.retry(options, newToken);
      return handler.resolve(retriedResponse);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (_) {
      return handler.next(err);
    }
  }

  String? _findHeaderKey(Map<String, dynamic> headers, String targetKey) {
    final lower = targetKey.toLowerCase();
    for (final key in headers.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }
}
