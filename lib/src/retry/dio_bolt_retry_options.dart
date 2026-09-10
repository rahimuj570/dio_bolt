import 'package:dio/dio.dart';

/// Internal key used in [RequestOptions.extra] to track the current network retry attempt count.
const String kDioBoltRetryCountKey = '_dioBoltRetryCount';

/// Internal key used in [RequestOptions.extra] to explicitly override retry behavior for a request.
const String kDioBoltRetryOverrideKey = '_dioBoltRetryOverride';

/// Extension on [Options] providing per-request retry configuration.
extension DioBoltRetryOptionsExtension on Options {
  /// Returns a copy of [Options] with explicit retry eligibility.
  ///
  /// - `enabled: true`: Marks the request as retry-eligible (even for normally non-retryable
  ///   methods like `POST`), provided the request payload is replayable.
  /// - `enabled: false`: Completely disables automatic retries for this request.
  Options copyWithRetry({bool enabled = true}) {
    final newExtra = Map<String, dynamic>.from(extra ?? {});
    newExtra[kDioBoltRetryOverrideKey] = enabled;
    return copyWith(extra: newExtra);
  }
}
