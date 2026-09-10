import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../transfer/dio_bolt_file.dart';
import '../transfer/dio_bolt_transfer_utils.dart';
import 'dio_bolt_retry_config.dart';

/// Pure decision engine that evaluates whether a failed request is eligible for retry.
class DioBoltRetryPolicy {
  /// The retry configuration.
  final DioBoltRetryConfig config;

  /// Creates a [DioBoltRetryPolicy].
  const DioBoltRetryPolicy({required this.config});

  /// Evaluates whether the request that produced [error] should be retried.
  Future<bool> shouldRetry(
    DioException error,
    RequestOptions options,
    int currentAttempt,
  ) async {
    // 1. Enforce maxRetries limit
    if (currentAttempt >= config.maxRetries) {
      return false;
    }

    // 2. Request body MUST be replayable (cannot be bypassed by overrides)
    if (!isReplayable(options.data, options)) {
      return false;
    }

    // 3. Check explicit per-request override
    final explicitOverride = options.extra[kDioBoltRetryOverrideKey];
    if (explicitOverride == false) {
      // Explicitly disabled for this request
      return false;
    }

    if (explicitOverride == true) {
      // Explicitly enabled by developer (bypasses method & standard status checks)
      // Custom evaluator still has final say
      if (config.retryEvaluator != null) {
        return await config.retryEvaluator!(error, options, currentAttempt + 1);
      }
      return true;
    }

    // 4. Validate HTTP method idempotency / safety
    final methodUpper = options.method.toUpperCase();
    final isMethodAllowed = config.retryableMethods
        .map((m) => m.toUpperCase())
        .contains(methodUpper);
    if (!isMethodAllowed) {
      return false;
    }

    // 5. Validate status code or transport error eligibility
    final statusCode = error.response?.statusCode;
    bool isErrorEligible = false;

    if (statusCode != null) {
      isErrorEligible = config.retryableStatusCodes.contains(statusCode);
    } else {
      isErrorEligible = config.retryableDioErrors.contains(error.type);
    }

    if (!isErrorEligible) {
      return false;
    }

    // 6. Invoke custom retry evaluator if provided
    if (config.retryEvaluator != null) {
      return await config.retryEvaluator!(error, options, currentAttempt + 1);
    }

    return true;
  }

  /// Evaluates whether [data] is safely replayable across multiple request attempts.
  ///
  /// Strictly permits:
  /// - `null`
  /// - `String`, `num`, `bool`
  /// - `Map`, `List`
  /// - `Uint8List`, `List<int>` byte buffers (non-Stream)
  /// - Safely replayable `FormData` or upload file lists
  ///
  /// Rejects `Stream`, one-shot stream data, and all unknown/custom body types.
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
    // Any Stream or unknown/custom body object is strictly non-replayable
    return false;
  }
}
