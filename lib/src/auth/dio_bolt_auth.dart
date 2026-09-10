import 'dart:async';
import 'package:dio/dio.dart';
import '../model/dio_bolt_response.dart';

export 'dio_bolt_auth_options.dart';

/// Callback to asynchronously retrieve the current access token.
typedef TokenProvider = FutureOr<String?> Function();

/// Callback to execute the refresh request using an isolated [refreshClient].
///
/// Must return the new access token string on success, or `null` if refresh failed.
typedef RefreshTokenRunner = FutureOr<String?> Function(Dio refreshClient);

/// Callback to persist the newly obtained access token.
///
/// If this throws or fails, the refresh is considered FAILED for safety.
typedef TokenStorageSaver = FutureOr<void> Function(String newToken);

/// Callback invoked when token refresh fails permanently (e.g. refresh token expired).
typedef RefreshFailureHandler = FutureOr<void> Function(
  DioBoltResponse originalResponse,
);

/// Public configuration for automatic token injection and 401 token refresh.
class DioBoltAuth {
  /// Asynchronously resolves the active access token.
  final TokenProvider getAccessToken;

  /// Executes the refresh call using an isolated Dio instance.
  final RefreshTokenRunner refreshToken;

  /// Invoked when a new token is obtained, allowing persistence to secure storage.
  final TokenStorageSaver? onTokenRefreshed;

  /// Invoked when refresh permanently fails (e.g. for triggering logout flow).
  final RefreshFailureHandler? onRefreshFailed;

  /// Header key to inject the token into. Defaults to `'Authorization'`.
  final String headerKey;

  /// Custom token formatter. Defaults to `'Bearer $token'`.
  final String Function(String token)? tokenHeaderBuilder;

  /// Creates a [DioBoltAuth] configuration.
  const DioBoltAuth({
    required this.getAccessToken,
    required this.refreshToken,
    this.onTokenRefreshed,
    this.onRefreshFailed,
    this.headerKey = 'Authorization',
    this.tokenHeaderBuilder,
  });
}
