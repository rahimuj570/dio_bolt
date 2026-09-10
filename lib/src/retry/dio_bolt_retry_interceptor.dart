import 'dart:async';
import 'package:dio/dio.dart';
import 'dio_bolt_retry_delay.dart';
import 'dio_bolt_retry_options.dart';
import 'dio_bolt_retry_policy.dart';

/// Callback invoked to log a retry event.
typedef RetryLogger = void Function(
  RequestOptions options,
  String reason,
  Duration delay,
  int attempt,
);

/// Interceptor managing network retry lifecycle, backoff delay,
/// cancellation unblocking, and retry execution.
class DioBoltRetryInterceptor extends Interceptor {
  /// The retry decision policy.
  final DioBoltRetryPolicy policy;

  /// The backoff and delay calculator.
  final DioBoltRetryDelay delayCalculator;

  /// The Dio instance used to execute the retried request.
  final Dio dio;

  /// Optional logger callback invoked on retry events.
  final RetryLogger? onRetryLog;

  /// Creates a [DioBoltRetryInterceptor].
  DioBoltRetryInterceptor({
    required this.policy,
    required this.dio,
    DioBoltRetryDelay? delayCalculator,
    this.onRetryLog,
  }) : delayCalculator = delayCalculator ?? DioBoltRetryDelay();

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final currentAttempt = (options.extra[kDioBoltRetryCountKey] as int?) ?? 0;

    // 1. Evaluate whether retry is permitted
    final eligible = await policy.shouldRetry(err, options, currentAttempt);
    if (!eligible) {
      return handler.next(err);
    }

    final nextAttempt = currentAttempt + 1;

    // 2. Calculate delay (including 429 Retry-After, exponential backoff, and jitter)
    final delay = delayCalculator.calculateDelay(
      attempt: nextAttempt,
      config: policy.config,
      error: err,
    );

    // 3. Log retry event safely
    if (onRetryLog != null) {
      final reason = err.response != null
          ? 'HTTP ${err.response!.statusCode}'
          : _formatDioErrorReason(err.type);
      try {
        onRetryLog!(options, reason, delay, nextAttempt);
      } catch (_) {
        // Logging failures must never impact request execution
      }
    }

    // 4. Cancellation-aware delay wait
    final cancelToken = options.cancelToken;
    if (cancelToken != null && cancelToken.isCancelled) {
      return handler.next(
        cancelToken.cancelError ??
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Request was cancelled before retry delay completed.',
            ),
      );
    }

    if (delay > Duration.zero) {
      try {
        await _waitForDelay(delay, cancelToken, options);
      } on DioException catch (cancelErr) {
        return handler.next(cancelErr);
      } catch (_) {
        return handler.next(err);
      }
    }

    // 5. Prepare retried RequestOptions with updated retry count and cloned payload
    final retryExtra = Map<String, dynamic>.from(options.extra);
    retryExtra[kDioBoltRetryCountKey] = nextAttempt;

    dynamic retryData = options.data;
    if (retryData is FormData) {
      retryData = retryData.clone();
    }

    final retryOptions = options.copyWith(
      extra: retryExtra,
      data: retryData,
    );

    // 6. Execute retry request
    try {
      final retriedResponse = await dio.fetch<dynamic>(retryOptions);
      return handler.resolve(retriedResponse);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (_) {
      return handler.next(err);
    }
  }

  Future<void> _waitForDelay(
    Duration delay,
    CancelToken? cancelToken,
    RequestOptions options,
  ) {
    if (cancelToken == null) {
      return Future.delayed(delay);
    }

    if (cancelToken.isCancelled) {
      throw cancelToken.cancelError ??
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Request was cancelled before retry delay.',
          );
    }

    final completer = Completer<void>();
    Timer? timer;

    void onCancel() {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          cancelToken.cancelError ??
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'Request was cancelled during retry delay.',
              ),
        );
      }
    }

    cancelToken.whenCancel.then((_) => onCancel()).catchError((_) {});

    timer = Timer(delay, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  String _formatDioErrorReason(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout';
      case DioExceptionType.sendTimeout:
        return 'Send timeout';
      case DioExceptionType.receiveTimeout:
        return 'Receive timeout';
      case DioExceptionType.connectionError:
        return 'Connection error';
      case DioExceptionType.badCertificate:
        return 'Bad certificate';
      case DioExceptionType.cancel:
        return 'Cancelled';
      default:
        return type.name;
    }
  }
}
