import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
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
    if (!isReplayable(options.data)) {
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
  /// - Safely replayable `FormData`
  ///
  /// Rejects `Stream`, one-shot stream data, and all unknown/custom body types.
  bool isReplayable(dynamic data) {
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
    if (data is FormData) {
      return _isFormDataReplayable(data);
    }
    // Any Stream or unknown/custom body object is strictly non-replayable
    return false;
  }

  /// Inspects [FormData] contents to ensure no one-shot or finalized streams exist.
  bool _isFormDataReplayable(FormData formData) {
    for (final entry in formData.files) {
      final file = entry.value;
      // If the file is already finalized, its stream cannot be read again
      if (file.isFinalized) {
        return false;
      }
      // If the file is backed purely by a Stream without length/bytes or file path,
      // it cannot be re-read safely.
      if (file.length == 0 && file.filename == null) {
        return false;
      }
    }
    return true;
  }
}
