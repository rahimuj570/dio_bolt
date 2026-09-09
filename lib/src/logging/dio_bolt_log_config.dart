/// Configuration options for Dio Bolt's request and response status logging.
class DioBoltLogConfig {
  /// Whether logging is enabled. Defaults to `true` when a config is provided.
  final bool enabled;

  /// Whether to use ANSI terminal colors for output (Green for success, Red for errors).
  final bool useColors;

  /// Custom printer function. Defaults to [print].
  ///
  /// Useful for redirecting logs to a custom sink or capturing logs during tests.
  final void Function(String message)? logPrint;

  /// Set of header and payload keys (case-insensitive) to redact with `[REDACTED]`.
  final Set<String> sensitiveKeys;

  /// Whether to include request headers in the log.
  final bool logHeaders;

  /// Whether to include query parameters in the log.
  final bool logQueryParameters;

  /// Whether to include request payloads in the log.
  final bool logRequestBody;

  /// Whether to include response data in the log.
  final bool logResponseBody;

  /// Default list of sensitive keys commonly containing secrets, credentials, or tokens.
  static const Set<String> defaultSensitiveKeys = {
    'authorization',
    'bearer',
    'token',
    'access_token',
    'refresh_token',
    'password',
    'secret',
    'api_key',
    'apikey',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  };

  /// Creates a [DioBoltLogConfig].
  const DioBoltLogConfig({
    this.enabled = true,
    this.useColors = true,
    this.logPrint,
    this.sensitiveKeys = defaultSensitiveKeys,
    this.logHeaders = true,
    this.logQueryParameters = true,
    this.logRequestBody = true,
    this.logResponseBody = true,
  });

  /// Creates a copy of this config with the given fields replaced.
  DioBoltLogConfig copyWith({
    bool? enabled,
    bool? useColors,
    void Function(String message)? logPrint,
    Set<String>? sensitiveKeys,
    bool? logHeaders,
    bool? logQueryParameters,
    bool? logRequestBody,
    bool? logResponseBody,
  }) {
    return DioBoltLogConfig(
      enabled: enabled ?? this.enabled,
      useColors: useColors ?? this.useColors,
      logPrint: logPrint ?? this.logPrint,
      sensitiveKeys: sensitiveKeys ?? this.sensitiveKeys,
      logHeaders: logHeaders ?? this.logHeaders,
      logQueryParameters: logQueryParameters ?? this.logQueryParameters,
      logRequestBody: logRequestBody ?? this.logRequestBody,
      logResponseBody: logResponseBody ?? this.logResponseBody,
    );
  }
}
