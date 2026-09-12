## 0.0.1

Initial release of Dio Bolt — a lightweight, production-grade HTTP networking layer built on top of Dio.

### Core Features
- **Universal Response Envelope**: Unified non-generic `DioBoltResponse` preserving HTTP status codes, complete raw server payloads (`responseData`), and cancellation states without throwing normal HTTP exceptions.
- **REST Request Methods**: Clean `get`, `post`, `put`, `patch`, and `delete` methods resolving directly to `DioBoltResponse`.
- **Authentication & Token Refresh**: `DioBoltAuth` with single-flight token refresh mutex on HTTP 401, persistence callbacks, automatic authenticated retry, and per-request `skipAuth()` control.
- **Resilient Retries**: `DioBoltRetryConfig` with exponential backoff, full jitter, `Retry-After` header parsing, idempotent method safeguards, and request replayability verification.
- **Upload & Download Subsystem**:
  - Replayable multipart uploads (`DioBoltFile.fromPath`, `DioBoltFile.fromBytes`) and one-shot streaming (`DioBoltFile.fromStream`).
  - Protected downloads with pre-flight conflict checks, isolated temporary staging, cleanup safeguards on failure/cancellation, and platform-hardened atomic file replacement.
  - In-memory `downloadBytes` for direct buffer downloads.
- **Developer-Friendly Logging**: `DioBoltLogConfig` with automatic sensitive-key redaction, cURL command generation, and zero-crash execution isolation.
- **Full Dio Interoperability**: Direct access to underlying `Dio` instance, options, interceptors, and transformer pipeline.