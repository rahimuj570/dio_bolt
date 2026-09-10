import 'package:dio/dio.dart';

/// Internal key used in [RequestOptions.extra] to bypass authentication and 401 refresh.
const String kDioBoltSkipAuthKey = '_dioBoltSkipAuth';

/// Internal key used in [RequestOptions.extra] to track whether a request was retried after 401.
const String kDioBoltAuthRetriedKey = '_dioBoltAuthRetried';

/// Extension on [Options] providing per-request authentication bypass.
extension DioBoltAuthOptionsExtension on Options {
  /// Returns a copy of [Options] that bypasses automatic token injection and 401 refresh.
  Options copyWithSkipAuth({bool skipAuth = true}) {
    final newExtra = Map<String, dynamic>.from(extra ?? {});
    newExtra[kDioBoltSkipAuthKey] = skipAuth;
    return copyWith(extra: newExtra);
  }
}
