<p align="center">
  <img src="assets/dio_bolt_logo.svg" alt="Dio Bolt logo" width="120">
</p>

<h1 align="center">Dio Bolt</h1>

<p align="center">
  A lightweight, production-focused Dart and Flutter HTTP networking layer built on top of <a href="https://pub.dev/packages/dio">Dio</a>.
</p>

<p align="center">
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.9+-0175C2.svg?logo=dart" alt="Dart"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.0+-02569B.svg?logo=flutter" alt="Flutter"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

---

Dio Bolt provides a clean API for REST API requests, standardized response handling, automatic access-token refresh, configurable HTTP retries with exponential backoff and jitter, structured API logging, multipart file uploads, and protected file downloads—while keeping the underlying `Dio` instance fully accessible.

## Features

- **Normalized Response Envelope (`DioBoltResponse`)**: Standardizes expected HTTP responses (2xx, 4xx, 5xx), transport errors, timeouts, and cancellations into a consistent `DioBoltResponse` without requiring repetitive `try/catch` boilerplate for expected network outcomes.
- **Complete Payload Preservation**: Server response bodies are never stripped or forced into an assumed schema. Access the raw response payload directly in `response.responseData`.
- **Centralized Authentication & Token Refresh**: Automatic `Authorization` header injection with single-flight token refresh coordination, retry-once loop protection, and token persistence hooks.
- **Resilient Network Retries**: Configurable exponential backoff, bounded jitter, server `Retry-After` header parsing, status/error eligibility checks, and request body replayability safeguards.
- **Safe Multipart Replayability**: Path- and byte-backed `DioBoltFile` uploads can be reconstructed for retries and authentication refresh, while one-shot streams and generic `FormData` are never automatically replayed.
- **Protected Two-Stage Downloads**: Downloads stream into temporary `.tmp` files with automatic parent directory creation, pre-flight collision checks, cleanup on failure/cancellation, and safe destination replacement.
- **Production Console Logger**: Clean, ANSI-colored request/response logs with automatic sensitive-key redaction (`[REDACTED]`), binary payload summaries, and isolated error handling.
- **Unrestricted Dio Access**: Direct access to the underlying `api.dio` instance at all times.
- **Pure Dart Core**: Zero UI dependencies, zero state-management lock-in, and zero code generation requirements.

---

## Why Dio Bolt?

While [Dio](https://pub.dev/packages/dio) is a powerful, flexible HTTP client for Dart and Flutter, building production applications often requires writing repetitive glue code around:

1. Wrapping every request in `try/catch` blocks to catch `DioException` on standard 4xx/5xx responses.
2. Managing concurrent 401 token refresh race conditions without duplicate refresh calls or infinite loops.
3. Writing exponential backoff and jitter retry loops that avoid retrying consumed multipart streams.
4. Handling download temporary files and directory creation safely.
5. Scrubbing authorization tokens and passwords from console logs.

Dio Bolt solves these challenges as a unified, cohesive networking layer:

```text
┌────────────────────────────────────────────────────────┐
│                    Your Application                    │
├────────────────────────────────────────────────────────┤
│                        Dio Bolt                        │
│   (Auth Refresh • Retry & Jitter • Safe Logs • Transfer)│
├────────────────────────────────────────────────────────┤
│                          Dio                           │
│     (Interceptors • Adapters • BaseOptions • Cache)    │
├────────────────────────────────────────────────────────┤
│                       HTTP / REST                      │
└────────────────────────────────────────────────────────┘
```

---

## Installation

Add `dio_bolt` to your `pubspec.yaml`:

```yaml
dependencies:
  dio_bolt: ^0.0.1
```

Or install via terminal:

```bash
dart pub add dio_bolt
```

> **Note:** `dio_bolt` re-exports common Dio types (`CancelToken`, `Options`, `FormData`, `MultipartFile`, `DioException`, `Response`), so you do not need to install `dio` separately for standard usage.

---

## Quick Start

```dart
import 'package:dio_bolt/dio_bolt.dart';

void main() async {
  // 1. Initialize client
  final api = DioBolt(
    options: BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
    enableLogging: true,
  );

  // 2. Make a request (expected network outcomes resolve to DioBoltResponse)
  final response = await api.get('/posts/1');

  // 3. Inspect the normalized envelope
  if (response.isSuccess) {
    print('HTTP ${response.statusCode}: ${response.responseData}');
  } else {
    print('Request failed (${response.statusCode}): ${response.message}');
  }
}
```

---

## Response Handling (`DioBoltResponse`)

All request methods in Dio Bolt resolve to a non-generic `DioBoltResponse`.

```dart
class DioBoltResponse {
  final bool isSuccess;       // true if HTTP statusCode is in the 200..299 range
  final int statusCode;       // HTTP status code (e.g. 200, 404, 500) or 0 for transport/cancellation
  final dynamic responseData; // Complete raw body from the server (Map, List, String, etc.)
  final String? message;      // Status message or error description
}
```

### Schema-Agnostic Response Data

Dio Bolt does not assume your API wraps responses in `{"data": ...}` or `{"success": true}`. The complete, unmodified server response is stored in `responseData`:

```dart
final response = await api.get('/users/42');

if (response.isSuccess) {
  final Map<String, dynamic> body = response.responseData;
  final user = User.fromJson(body);
  print('Loaded user: ${user.name}');
} else if (response.statusCode == 404) {
  print('User not found: ${response.message}');
} else if (response.statusCode == 0) {
  print('Network / connection failure: ${response.message}');
}
```

---

## HTTP Requests

Dio Bolt provides clean methods for standard REST operations: `get`, `post`, `put`, `patch`, and `delete`.

### GET Request

```dart
final response = await api.get(
  '/products',
  queryParameters: {'category': 'electronics', 'page': 1},
  headers: {'X-Custom-Header': 'value'},
);
```

### POST Request

```dart
final response = await api.post(
  '/products',
  data: {
    'title': 'Mechanical Keyboard',
    'price': 99.99,
  },
);
```

### PUT & PATCH Requests

```dart
// Replace resource
final putResponse = await api.put(
  '/products/101',
  data: {'title': 'Updated Title', 'price': 89.99},
);

// Partially update resource
final patchResponse = await api.patch(
  '/products/101',
  data: {'price': 79.99},
);
```

### DELETE Request

```dart
final deleteResponse = await api.delete('/products/101');
```

---

## Error Handling

Dio Bolt normalizes expected HTTP errors and transport failures into `DioBoltResponse`:

| Scenario | `isSuccess` | `statusCode` | `responseData` | `message` |
| :--- | :---: | :---: | :---: | :--- |
| **HTTP 2xx (Success)** | `true` | `200`–`299` | Server payload | Status text (e.g. `'OK'`) |
| **HTTP 4xx / 5xx (Server Error)** | `false` | `400`–`599` | Complete error payload | Server message or default status text |
| **Timeout (Connection/Send/Receive)** | `false` | `0` | `null` | Detailed timeout description |
| **Connection Failure / Offline** | `false` | `0` | `null` | `'Unable to connect to the server.'` |
| **Request Cancelled** | `false` | `0` | `null` | `'Request was cancelled.'` |

Because expected HTTP and transport failures resolve to `DioBoltResponse`, callers do not require repetitive `try/catch` blocks for routine network outcomes:

```dart
final response = await api.get('/dashboard');

if (response.isSuccess) {
  renderDashboard(response.responseData);
} else {
  showErrorSnackbar(response.message ?? 'An error occurred.');
}
```

---

## Authentication & Token Refresh

Dio Bolt includes built-in single-flight token refresh coordination that prevents concurrent 401 storms and race conditions.

```dart
final api = DioBolt(
  auth: DioBoltAuth(
    // 1. Resolve current access token
    getAccessToken: () async => await secureStorage.read(key: 'jwt_token'),

    // 2. Perform refresh call using the isolated refresh client
    refreshToken: (refreshClient) async {
      final refreshToken = await secureStorage.read(key: 'refresh_token');
      final res = await refreshClient.post(
        'https://api.example.com/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return res.data['accessToken'];
    },

    // 3. Hook to persist the refreshed token
    onTokenRefreshed: (newToken) async {
      await secureStorage.write(key: 'jwt_token', value: newToken);
    },

    // 4. Hook invoked when refresh fails permanently (e.g. refresh token expired)
    onRefreshFailed: (originalResponse) async {
      await secureStorage.deleteAll();
      navigatorKey.currentState?.pushReplacementNamed('/login');
    },

    // Optional customizations:
    headerKey: 'Authorization',                     // Default: 'Authorization'
    tokenHeaderBuilder: (token) => 'Bearer $token', // Default: 'Bearer $token'
  ),
);
```

### Authentication Features

- **Single-Flight Coordination**: When multiple concurrent requests encounter a `401`, exactly **one** refresh request is executed. All other pending requests await that single result before retrying.
- **Retry-Once Protection**: Retried requests are marked internally to prevent infinite refresh loops.
- **Caller Header Preservation**: If a caller explicitly supplies a custom authorization header on a specific request, it is preserved without being overwritten.
- **403 Forbidden Behavior**: HTTP 403 responses do not trigger a token refresh attempt.
- **Cancellation Awareness**: Cancelling a request while waiting for a token refresh unblocks immediately.
- **Replayability Protection**: Only replayable requests (e.g., standard bodies or path-/byte-backed uploads) participate in auth retry; non-replayable streams return the original 401 response.
- **Bypass Authentication**: Use `Options().copyWithSkipAuth()` to bypass token injection and 401 refresh on public endpoints:

```dart
final loginResponse = await api.post(
  '/auth/login',
  data: {'username': 'user', 'password': 'secret'},
  options: Options().copyWithSkipAuth(),
);
```

---

## Network Retry & Resilience

Dio Bolt features an automated network retry interceptor that respects idempotency, exponential backoff, jitter, and HTTP `429 Retry-After` headers.

```dart
final api = DioBolt(
  retryConfig: DioBoltRetryConfig(
    maxRetries: 3,                                    // Max retry attempts
    initialDelay: const Duration(milliseconds: 500),  // Base backoff delay
    maxDelay: const Duration(seconds: 5),             // Maximum delay cap
    backoffMultiplier: 2.0,                           // Exponential multiplier
    useJitter: true,                                  // Adds random 0%-20% variance
    respectRetryAfter: true,                          // Parses server 429 Retry-After headers
    clampRetryAfterToMaxDelay: true,                  // Clamps Retry-After to maxDelay
    retryableStatusCodes: {408, 429, 500, 502, 503, 504},
    retryableMethods: {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'}, // POST/PATCH excluded by default
  ),
);
```

### Delay Calculation Precedence

1. **Custom `delayCalculator`** (if provided) takes full precedence over default computation.
2. **`Retry-After` Header**: On HTTP 429, parses delta-seconds or HTTP-date (clamped to `maxDelay` if configured).
3. **Exponential Backoff**: Computes `initialDelay * (backoffMultiplier ^ (attempt - 1))`, clamped to `maxDelay`.
4. **Jitter**: If `useJitter: true`, adds a random 0%–20% variance (capped at `maxDelay`) to avoid synchronized thundering herds.

### Safe Method Idempotency & Per-Request Opt-In

By default, non-idempotent methods (`POST` and `PATCH`) are **not** retried. You can explicitly opt-in to retries for specific requests using `copyWithRetry`:

```dart
final response = await api.post(
  '/idempotent-order',
  data: {'orderId': 'ORD-1234'},
  options: Options().copyWithRetry(enabled: true),
);
```

### Request Replayability Rules

The retry policy verifies request body replayability before scheduling retries:
- In-memory bodies (`Map`, `List`, `String`, `num`, `Uint8List`) $\rightarrow$ **Replayable**
- Path-backed / Byte-backed uploads (`DioBoltFile.fromPath`, `DioBoltFile.fromBytes`) $\rightarrow$ **Replayable**
- One-shot streams (`Stream<List<int>>`, `DioBoltFile.fromStream`, generic `FormData`) $\rightarrow$ **Strictly Non-Replayable** (will not be retried)

---

## Production Console Logging

Enable sanitized, structured logging for debugging:

```dart
final api = DioBolt(
  enableLogging: true, // Simple one-flag enable
  // Or custom configuration:
  logConfig: DioBoltLogConfig(
    enabled: true,
    useColors: true,             // ANSI terminal colors
    logHeaders: true,
    logQueryParameters: true,
    logRequestBody: true,
    logResponseBody: true,
    sensitiveKeys: {             // Keys masked with [REDACTED]
      'authorization',
      'password',
      'token',
      'secret',
      'api_key',
    },
  ),
);
```

### Example Console Output

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 DIO BOLT • REQUEST [#1]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
METHOD   : GET
URL      : https://api.example.com/v1/profile
PATH     : /v1/profile
QUERY    : none
HEADERS  : {
  "Authorization": "[REDACTED]"
}
PAYLOAD  : none
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ DIO BOLT • RESPONSE [#1]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
METHOD        : GET
URL           : https://api.example.com/v1/profile
STATUS        : 200 OK
DURATION      : 142 ms
RESPONSE DATA :
{
  "id": 101,
  "username": "developer",
  "email": "dev@example.com"
}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> **Safety:** Logging handles formatting and printing errors internally, ensuring logger issues do not interfere with normal request dispatching.

---

## File Uploads

Upload files using `DioBoltFile` descriptors. Dio Bolt automatically constructs `FormData` and recreates fresh multipart streams on retries or token refreshes.

```dart
// 1. Single file from path
final response = await api.upload(
  '/users/avatar',
  file: DioBoltFile.fromPath(
    '/path/to/avatar.png',
    fieldName: 'avatar',
    filename: 'avatar.png',
    contentType: 'image/png',
  ),
  data: {'userId': '123'},
  onSendProgress: (sent, total) {
    print('Upload progress: ${(sent / total * 100).toStringAsFixed(0)}%');
  },
);

// 2. Multiple files from bytes and paths
final multiResponse = await api.upload(
  '/documents/batch',
  files: [
    DioBoltFile.fromBytes(
      pdfBytes,
      fieldName: 'documents[]',
      filename: 'report.pdf',
      contentType: 'application/pdf',
    ),
    DioBoltFile.fromPath(
      '/path/to/notes.txt',
      fieldName: 'documents[]',
      filename: 'notes.txt',
    ),
  ],
  data: {'category': 'finance'},
);
```

### `DioBoltFile` Constructors & Replayability

| Constructor | Replayability on Retry / 401 | Use Case |
| :--- | :---: | :--- |
| `DioBoltFile.fromPath(path, ...)` | **Yes** (Re-reads from disk) | Files stored on local filesystem |
| `DioBoltFile.fromBytes(bytes, ...)` | **Yes** (Re-reads byte buffer) | In-memory files, byte buffers |
| `DioBoltFile.fromStream(stream, length: ..., ...)` | **No** (One-shot stream) | Live stream feeds |

---

## File Downloads

Download files with protected two-stage buffering:

```dart
final response = await api.download(
  'https://example.com/files/archive.zip',
  savePath: '/local/storage/downloads/archive.zip',
  overwrite: true, // Default: true
  onReceiveProgress: (received, total) {
    if (total > 0) {
      print('Download: ${(received / total * 100).toStringAsFixed(0)}%');
    }
  },
);

if (response.isSuccess) {
  print('Saved to: ${response.responseData}'); // Returns final savePath
}
```

### Two-Stage Download Lifecycle

1. **Automatic Directory Creation**: Parent directories are created recursively before the download begins.
2. **Pre-Flight Conflict Checking**: If `overwrite: false` and the destination already exists, Dio Bolt returns a conflict response before dispatching a network request.
3. **In-Flight Destination Protection**: Existing destination files are never deleted or modified while the download is in progress.
4. **Temporary File Buffering**: Network data is streamed into an adjacent `.tmp` file.
5. **Safe Destination Replacement**: Upon 100% completion, the temporary file is moved to `savePath`. On platforms where direct rename over an existing file is rejected (e.g. Windows), a two-phase backup swap with rollback protection is performed.
6. **Automatic Cleanup**: Temporary `.tmp` files are cleaned up on HTTP errors, transport failures, cancellations, or retries.

### In-Memory Byte Downloads (`downloadBytes`)

To download binary payloads directly into memory without writing to disk:

```dart
final response = await api.downloadBytes('https://example.com/image.png');

if (response.isSuccess) {
  final Uint8List bytes = response.responseData;
  print('Downloaded ${bytes.length} bytes into memory');
}
```

---

## Request Cancellation

Use Dio's `CancelToken` across all requests, uploads, and downloads:

```dart
final cancelToken = CancelToken();

// Dispatch request
final future = api.download(
  '/large-video.mp4',
  savePath: '/storage/video.mp4',
  cancelToken: cancelToken,
);

// Cancel the operation
cancelToken.cancel('User navigated away');

final response = await future;
print(response.isSuccess);  // false
print(response.statusCode); // 0
print(response.message);    // 'Request was cancelled.'
```

---

## Direct Dio Access (Escape Hatch)

Dio Bolt does not hide Dio. You can access the underlying `Dio` instance whenever you need direct control:

```dart
final rawDio = api.dio;

// Add third-party interceptors, custom transformers, or custom HTTP adapters:
rawDio.interceptors.add(MyCustomInterceptor());
rawDio.options.connectTimeout = const Duration(seconds: 15);
```

---

## What Dio Bolt Intentionally Does NOT Do

To maintain architectural clarity and avoid unnecessary coupling, Dio Bolt intentionally does not provide:

- **No State Management Lock-in**: Compatible with Bloc, Riverpod, Provider, Signals, or plain Dart/Flutter state.
- **No UI Dependencies**: Pure Dart core that runs across Flutter and standalone Dart applications.
- **No Model Codegen / Reflection**: Response mapping is handled directly with standard Dart functions (`fromJson`).
- **No Built-in Caching**: Dio Bolt does not enforce a client-side cache store. Attach standard Dio caching interceptors to `api.dio` if caching is needed.

---

## Testing & Verification

Dio Bolt includes an automated test suite covering response handling, authentication single-flight coordination, retry backoff algorithms, console logging, cancellation, uploads, and downloads.

Run the test suite and static analyzer:

```bash
dart analyze
dart test
dart run example/main.dart
```

---

## Compatibility

- **Dart SDK**: `^3.9.0`
- **Flutter**: `3.0+`
- **Dio**: `^5.11.1`
- **Supported Platforms**: Android, iOS, macOS, Windows, Linux, and Server. (Disk-based file paths require filesystem access via `dart:io`; in-memory operations and standard HTTP requests work across all platforms supported by Dio).

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.