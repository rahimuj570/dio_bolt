import 'package:dio/dio.dart';

/// A universal, normalized response envelope for all HTTP and network outcomes.
///
/// Every request method in [DioBolt] resolves to a [DioBoltResponse] without
/// throwing exceptions for normal HTTP or network failures.
class DioBoltResponse {
  /// Indicates whether the HTTP request was successful (status code 200-299).
  final bool isSuccess;

  /// The HTTP status code of the response, or `0` if no HTTP response was received (e.g. transport failure).
  final int statusCode;

  /// The complete raw response body received from the server.
  final dynamic responseData;

  /// A human-readable status or error message.
  final String? message;

  /// Creates a [DioBoltResponse].
  const DioBoltResponse({
    required this.isSuccess,
    required this.statusCode,
    this.responseData,
    this.message,
  });

  /// Factory constructor that converts a Dio [Response] into a [DioBoltResponse].
  factory DioBoltResponse.fromResponse(Response response) {
    final statusCode = response.statusCode ?? 0;
    final isSuccess = statusCode >= 200 && statusCode < 300;

    return DioBoltResponse(
      isSuccess: isSuccess,
      statusCode: statusCode,
      responseData: response.data,
      message: response.statusMessage,
    );
  }

  /// Factory constructor that converts a [DioException] into a [DioBoltResponse].
  factory DioBoltResponse.fromDioException(DioException exception) {
    final response = exception.response;
    if (response != null) {
      final statusCode = response.statusCode ?? 0;
      final isSuccess = statusCode >= 200 && statusCode < 300;
      final message =
          response.statusMessage ?? _defaultMessageForStatus(statusCode);

      return DioBoltResponse(
        isSuccess: isSuccess,
        statusCode: statusCode,
        responseData: response.data,
        message: message,
      );
    }

    return DioBoltResponse(
      isSuccess: false,
      statusCode: 0,
      responseData: null,
      message: _messageForDioExceptionType(exception),
    );
  }

  static String _messageForDioExceptionType(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out.';
      case DioExceptionType.sendTimeout:
        return 'Request sending timed out.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Response receiving timed out.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Secure connection could not be established.';
      case DioExceptionType.badResponse:
        return 'Invalid response from server.';
      case DioExceptionType.unknown:
        return exception.message ?? 'An unexpected network error occurred.';
    }
  }

  static String _defaultMessageForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request.';
      case 401:
        return 'Unauthorized access.';
      case 403:
        return 'Forbidden request.';
      case 404:
        return 'Resource not found.';
      case 409:
        return 'Request conflict occurred.';
      case 422:
        return 'Unprocessable entity.';
      case 429:
        return 'Too many requests. Rate limit exceeded.';
      default:
        if (statusCode >= 500 && statusCode < 600) {
          return 'Server error occurred.';
        } else if (statusCode >= 400 && statusCode < 500) {
          return 'Client request error ($statusCode).';
        }
        return 'HTTP $statusCode';
    }
  }

  @override
  String toString() =>
      'DioBoltResponse(statusCode: $statusCode, isSuccess: $isSuccess, message: $message, responseData: $responseData)';
}
