import 'dart:async';
import 'package:dio/dio.dart';
import '../logging/dio_bolt_log_config.dart';
import '../logging/dio_bolt_logging_interceptor.dart';
import '../model/dio_bolt_response.dart';
import 'dio_bolt_auth.dart';

/// Coordinates single-flight token refresh, isolated client execution,
/// strict token persistence, and safe failure dispatching.
class DioBoltRefreshManager {
  /// The user-provided authentication configuration.
  final DioBoltAuth auth;

  /// The isolated Dio client used exclusively for refresh requests.
  final Dio refreshClient;

  Future<String?>? _activeRefreshFuture;

  /// Creates a [DioBoltRefreshManager].
  DioBoltRefreshManager({
    required this.auth,
    required this.refreshClient,
  });

  /// Factory constructor that builds an isolated refresh [Dio] instance
  /// copying appropriate baseline networking options without recursive interceptors.
  factory DioBoltRefreshManager.fromDio({
    required DioBoltAuth auth,
    required Dio mainDio,
    DioBoltLogConfig? logConfig,
  }) {
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: mainDio.options.baseUrl,
        connectTimeout: mainDio.options.connectTimeout,
        sendTimeout: mainDio.options.sendTimeout,
        receiveTimeout: mainDio.options.receiveTimeout,
        responseType: mainDio.options.responseType,
        contentType: mainDio.options.contentType,
        validateStatus: mainDio.options.validateStatus,
      ),
    );

    // Share transformer and adapter (essential for connection pooling and mock testing)
    refreshDio.transformer = mainDio.transformer;
    refreshDio.httpClientAdapter = mainDio.httpClientAdapter;

    // Attach logger if logging is active, but NEVER attach DioBoltAuthInterceptor
    if (logConfig != null && logConfig.enabled) {
      refreshDio.interceptors.add(
        DioBoltLoggingInterceptor(config: logConfig),
      );
    }

    return DioBoltRefreshManager(
      auth: auth,
      refreshClient: refreshDio,
    );
  }

  /// Executes or joins an ongoing single-flight token refresh operation.
  ///
  /// Guarantees that:
  /// 1. Exactly one refresh request runs per concurrent 401 wave.
  /// 2. Strict persistence is enforced before a new token is deemed usable.
  /// 3. [DioBoltAuth.onRefreshFailed] is called **at most once per refresh cycle**.
  /// 4. Slot cleanup is reference-safe via [identical].
  Future<String?> refreshToken(DioBoltResponse initiating401Response) {
    if (_activeRefreshFuture != null) {
      return _activeRefreshFuture!;
    }

    final completer = Completer<String?>();
    final currentFuture = completer.future;
    _activeRefreshFuture = currentFuture;

    () async {
      String? newToken;
      bool success = false;

      try {
        newToken = await auth.refreshToken(refreshClient);

        if (newToken != null && newToken.isNotEmpty) {
          // Strict persistence: If onTokenRefreshed throws, the refresh is deemed failed.
          if (auth.onTokenRefreshed != null) {
            await auth.onTokenRefreshed!(newToken);
          }
          success = true;
          completer.complete(newToken);
        } else {
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      } finally {
        // Dispatch onRefreshFailed exactly once per refresh cycle if refresh failed
        if (!success) {
          try {
            await auth.onRefreshFailed?.call(initiating401Response);
          } catch (_) {
            // Callback exceptions must not escape
          }
        }

        // Reference-safe cleanup
        if (identical(_activeRefreshFuture, currentFuture)) {
          _activeRefreshFuture = null;
        }
      }
    }();

    return currentFuture;
  }

  /// Waits for token refresh while immediately unblocking if [cancelToken] is cancelled.
  Future<String?> waitForTokenOrCancel(
    DioBoltResponse initiating401Response,
    CancelToken? cancelToken,
  ) async {
    if (cancelToken == null) {
      return refreshToken(initiating401Response);
    }

    if (cancelToken.isCancelled) {
      throw cancelToken.cancelError ??
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
            message: 'Request was cancelled before token refresh completed.',
          );
    }

    final refreshFuture = refreshToken(initiating401Response);
    final cancelCompleter = Completer<String?>();

    void onCancel() {
      if (!cancelCompleter.isCompleted) {
        cancelCompleter.completeError(
          cancelToken.cancelError ??
              DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.cancel,
                message:
                    'Request was cancelled while waiting for token refresh.',
              ),
        );
      }
    }

    cancelToken.whenCancel.then((_) => onCancel()).catchError((_) {});

    return Future.any([refreshFuture, cancelCompleter.future]);
  }
}
