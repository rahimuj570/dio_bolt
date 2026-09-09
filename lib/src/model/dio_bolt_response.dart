/// A normalized HTTP response envelope that preserves the complete raw response body.
class DioBoltResponse {
  /// Indicates whether the HTTP request was successful (status code 200-299).
  final bool isSuccess;

  /// The HTTP status code of the response.
  final int statusCode;

  /// The complete raw response body received from the server.
  final dynamic responseData;

  /// An optional status or error message (e.g. from HTTP statusMessage).
  final String? message;

  /// Creates a [DioBoltResponse].
  const DioBoltResponse({
    required this.isSuccess,
    required this.statusCode,
    this.responseData,
    this.message,
  });

  @override
  String toString() =>
      'DioBoltResponse(statusCode: $statusCode, isSuccess: $isSuccess, message: $message, responseData: $responseData)';
}