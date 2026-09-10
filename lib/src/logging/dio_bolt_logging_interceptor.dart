import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'dio_bolt_log_config.dart';

/// Internal key used to store request start time in [RequestOptions.extra].
const String _kStartTimeKey = '_dioBoltStartTime';

/// Internal key used to store request correlation ID in [RequestOptions.extra].
const String _kRequestIdKey = '_dioBoltRequestId';

/// ANSI escape codes for terminal coloring.
class _Ansi {
  static const reset = '\x1B[0m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const cyan = '\x1B[36m';
}

/// An observational Dio interceptor providing readable, production-safe console logs.
///
/// Designed to be non-intrusive, zero-crash, and independent of any UI framework.
class DioBoltLoggingInterceptor extends Interceptor {
  /// The active logging configuration.
  final DioBoltLogConfig config;

  int _requestCounter = 0;

  /// Creates a [DioBoltLoggingInterceptor].
  DioBoltLoggingInterceptor({this.config = const DioBoltLogConfig()});

  void _print(String message) {
    if (config.logPrint != null) {
      config.logPrint!(message);
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  String _applyColor(String text, String colorCode) {
    if (!config.useColors) return text;
    final lines = text.split('\n');
    return lines.map((line) => '$colorCode$line${_Ansi.reset}').join('\n');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!config.enabled) {
      return handler.next(options);
    }

    try {
      final reqId = ++_requestCounter;
      options.extra[_kRequestIdKey] = reqId;
      options.extra[_kStartTimeKey] = DateTime.now().millisecondsSinceEpoch;

      final buffer = StringBuffer();
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('🚀 DIO BOLT • REQUEST [#$reqId]');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('METHOD   : ${options.method.toUpperCase()}');
      buffer.writeln('URL      : ${options.uri}');
      buffer.writeln('PATH     : ${options.path}');

      if (config.logQueryParameters) {
        if (options.queryParameters.isNotEmpty) {
          buffer.writeln(
            'QUERY    : ${_formatData(options.queryParameters, sanitize: true)}',
          );
        } else {
          buffer.writeln('QUERY    : none');
        }
      }

      if (config.logHeaders) {
        if (options.headers.isNotEmpty) {
          final sanitizedHeaders = _sanitizeHeaders(options.headers);
          buffer.writeln(
            'HEADERS  : ${_formatData(sanitizedHeaders, sanitize: false)}',
          );
        } else {
          buffer.writeln('HEADERS  : none');
        }
      }

      if (config.logRequestBody) {
        buffer.writeln('PAYLOAD  : ${_formatPayload(options.data)}');
      }

      buffer.write('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      _print(_applyColor(buffer.toString(), _Ansi.cyan));
    } catch (_) {
      // Safety guarantee: Logger must never cause request failure.
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!config.enabled) {
      return handler.next(response);
    }

    try {
      final statusCode = response.statusCode ?? 0;
      final isSuccess = statusCode >= 200 && statusCode < 300;
      final reqId = response.requestOptions.extra[_kRequestIdKey] ?? '?';
      final durationStr = _calculateDuration(response.requestOptions);

      final buffer = StringBuffer();
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (isSuccess) {
        buffer.writeln('✅ DIO BOLT • RESPONSE [#$reqId]');
      } else {
        buffer.writeln('❌ DIO BOLT • RESPONSE [#$reqId]');
      }
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(
        'METHOD        : ${response.requestOptions.method.toUpperCase()}',
      );
      buffer.writeln('URL           : ${response.requestOptions.uri}');
      buffer.writeln(
        'STATUS        : $statusCode ${response.statusMessage ?? ''}'.trim(),
      );
      buffer.writeln('DURATION      : $durationStr');

      if (config.logResponseBody) {
        buffer.writeln('RESPONSE DATA :');
        buffer.writeln(_formatResponseData(response.data));
      }

      buffer.write('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final color = isSuccess ? _Ansi.green : _Ansi.red;
      _print(_applyColor(buffer.toString(), color));
    } catch (_) {
      // Safety guarantee: Logger must never cause request failure.
    }

    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!config.enabled) {
      return handler.next(err);
    }

    try {
      final reqId = err.requestOptions.extra[_kRequestIdKey] ?? '?';
      final durationStr = _calculateDuration(err.requestOptions);
      final response = err.response;

      final buffer = StringBuffer();
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (response != null) {
        // HTTP 4xx / 5xx error response
        final statusCode = response.statusCode ?? 0;
        buffer.writeln('❌ DIO BOLT • RESPONSE [#$reqId]');
        buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        buffer.writeln(
          'METHOD        : ${err.requestOptions.method.toUpperCase()}',
        );
        buffer.writeln('URL           : ${err.requestOptions.uri}');
        buffer.writeln(
          'STATUS        : $statusCode ${response.statusMessage ?? _defaultHttpStatusMessage(statusCode)}'
              .trim(),
        );
        buffer.writeln('DURATION      : $durationStr');

        if (config.logResponseBody) {
          buffer.writeln('RESPONSE DATA :');
          buffer.writeln(_formatResponseData(response.data));
        }
      } else {
        // Transport / Network / Timeout error
        buffer.writeln('❌ DIO BOLT • NETWORK ERROR [#$reqId]');
        buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        buffer.writeln(
          'METHOD     : ${err.requestOptions.method.toUpperCase()}',
        );
        buffer.writeln('URL        : ${err.requestOptions.uri}');
        buffer.writeln('ERROR TYPE : ${err.type.name}');
        buffer.writeln('DURATION   : $durationStr');
        buffer.writeln('STATUS     : No HTTP response');
        buffer.writeln('MESSAGE    : ${_networkErrorMessage(err)}');
      }

      buffer.write('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      _print(_applyColor(buffer.toString(), _Ansi.red));
    } catch (_) {
      // Safety guarantee: Logger must never cause request failure.
    }

    return handler.next(err);
  }

  String _calculateDuration(RequestOptions options) {
    final startTime = options.extra[_kStartTimeKey] as int?;
    if (startTime == null) return '0 ms';
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startTime;
    if (elapsedMs < 1000) {
      return '$elapsedMs ms';
    }
    return '${(elapsedMs / 1000).toStringAsFixed(1)} s';
  }

  String _networkErrorMessage(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out';
      case DioExceptionType.sendTimeout:
        return 'Request sending timed out';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Response receiving timed out';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server';
      case DioExceptionType.cancel:
        return 'Request was cancelled';
      case DioExceptionType.badCertificate:
        return 'Secure connection could not be established';
      case DioExceptionType.badResponse:
        return 'Invalid response received from server';
      case DioExceptionType.unknown:
        return err.message ?? 'An unexpected network failure occurred';
    }
  }

  String _defaultHttpStatusMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 409:
        return 'Conflict';
      case 422:
        return 'Unprocessable Entity';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      default:
        return '';
    }
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final result = <String, dynamic>{};
    for (final entry in headers.entries) {
      final keyLower = entry.key.toLowerCase();
      final isSensitive = config.sensitiveKeys.any(
        (s) => keyLower.contains(s.toLowerCase()),
      );
      result[entry.key] = isSensitive ? '[REDACTED]' : entry.value;
    }
    return result;
  }

  dynamic _sanitizeData(dynamic data) {
    if (data is Map) {
      final result = <String, dynamic>{};
      for (final entry in data.entries) {
        final keyStr = entry.key.toString();
        final keyLower = keyStr.toLowerCase();
        final isSensitive = config.sensitiveKeys.any(
          (s) => keyLower.contains(s.toLowerCase()),
        );
        if (isSensitive) {
          result[keyStr] = '[REDACTED]';
        } else {
          result[keyStr] = _sanitizeData(entry.value);
        }
      }
      return result;
    } else if (data is List) {
      return data.map((e) => _sanitizeData(e)).toList();
    }
    return data;
  }

  String _formatPayload(dynamic data) {
    if (data == null) return 'none';

    if (data is FormData) {
      final fields = <String, String>{};
      for (final field in data.fields) {
        final keyLower = field.key.toLowerCase();
        final isSensitive = config.sensitiveKeys.any(
          (s) => keyLower.contains(s.toLowerCase()),
        );
        fields[field.key] = isSensitive ? '[REDACTED]' : field.value;
      }
      final files = data.files.map((entry) {
        final file = entry.value;
        return '${entry.key}: MultipartFile [filename: ${file.filename}, length: ${file.length} bytes, contentType: ${file.contentType}]';
      }).toList();

      final buffer = StringBuffer('FormData\n');
      if (fields.isNotEmpty) {
        buffer.writeln('  Fields:');
        fields.forEach((k, v) => buffer.writeln('    $k: $v'));
      }
      if (files.isNotEmpty) {
        buffer.writeln('  Files:');
        for (final f in files) {
          buffer.writeln('    $f');
        }
      }
      return buffer.toString().trimRight();
    }

    if (data is Uint8List) {
      return '<binary data: ${_formatBytes(data.length)}>';
    }

    if (data is Stream) {
      return '<Stream data>';
    }

    return _formatData(data, sanitize: true);
  }

  String _formatResponseData(dynamic data) {
    if (data == null || (data is String && data.isEmpty)) return 'null';

    if (data is Uint8List) {
      return '<binary data: ${_formatBytes(data.length)}>';
    }

    if (data is Stream) {
      return '<Stream data>';
    }

    return _formatData(data, sanitize: false);
  }

  String _formatData(dynamic data, {required bool sanitize}) {
    final targetData = sanitize ? _sanitizeData(data) : data;
    try {
      if (targetData is Map || targetData is List) {
        return const JsonEncoder.withIndent('  ').convert(targetData);
      }
      return targetData.toString();
    } catch (_) {
      return targetData.toString();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Logs a retry event to the console.
  void logRetry({
    required RequestOptions options,
    required String reason,
    required Duration delay,
    required int attempt,
  }) {
    if (!config.enabled) return;

    try {
      final buffer = StringBuffer();
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('🔄 DIO BOLT • RETRY [#$attempt]');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('METHOD   : ${options.method.toUpperCase()}');
      buffer.writeln('URL      : ${options.uri}');
      buffer.writeln('REASON   : $reason');
      buffer.writeln('DELAY    : ${_formatDuration(delay)}');
      buffer.write('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final colored = _applyColor(buffer.toString(), _Ansi.yellow);
      _print(colored);
    } catch (_) {
      // Zero-crash guarantee
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    final seconds = (duration.inMilliseconds / 1000).toStringAsFixed(1);
    return '${seconds}s';
  }
}
