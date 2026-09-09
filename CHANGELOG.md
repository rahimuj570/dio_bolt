## 0.0.1

- Initial release.
- **Phase 1**: Core `DioBolt` facade wrapping Dio.
- **Phase 2**: Two-level networking API:
  - Raw/Flexible API (`get`, `post`, `put`, `patch`, `delete`) returning schema-agnostic `DioBoltResponse`.
  - Typed Convenience API (`getAs`, `postAs`, `putAs`, `patchAs`, `deleteAs`) accepting `fromJson`.
- **Phase 3**: Production-grade exception and error handling:
  - Introduced `DioBoltException` and `DioBoltExceptionType`.
  - Added centralized `DioExceptionMapper` for normalizing HTTP status codes and network/timeout failures.
  - Complete error payload preservation in `DioBoltException.responseData`.
  - Added `DioBoltExceptionType.decodingError` for safe `fromJson` parsing error handling.