# Dio Bolt

> "Dio Bolt is a lightweight production networking layer built on top of Dio. It removes repetitive networking boilerplate while keeping Dio fully accessible."

Dio Bolt enhances Dio rather than replacing or hiding it. It provides two clean, complementary levels of networking API while keeping the raw Dio instance fully accessible whenever needed.

---

## Two Levels of Networking API

> **Core Principle:**
> Dio Bolt does not assume your backend response structure. The raw API gives you the complete response body, while the `getAs<T>()` family lets you explicitly convert that body into your application model.

### 1. Raw / Flexible API (`get`, `post`, `put`, `patch`, `delete`)

Returns a normalized, non-generic `DioBoltResponse` that preserves the **complete** response body in `responseData`.

```dart
final response = await api.get('/users');

if (response.isSuccess) {
  final data = response.responseData;
  print('HTTP status: ${response.statusCode}');
  print('Raw body: $data');
}
```

Because `dio_bolt` does not automatically reduce or extract specific keys, you have total freedom to handle any backend schema:

```dart
final response = await api.get('/users?page=1');

if (response.isSuccess) {
  // Directly access custom metadata, pagination, or result wrappers
  final users = response.responseData['data'];
  final pagination = response.responseData['pagination'];
}
```

### 2. Typed Convenience API (`getAs`, `postAs`, `putAs`, `patchAs`, `deleteAs`)

For developers who want direct model conversion, the `getAs<T>()` family accepts an explicit `fromJson` callback that receives the complete response body:

```dart
// Single Entity
final User user = await api.getAs<User>(
  '/users/1',
  fromJson: User.fromJson,
);
```

#### Paginated & Wrapped Responses

Because `fromJson` receives the entire response body, paginated APIs remain an application-level concern without framework restrictions:

```dart
class UserPage {
  final List<User> users;
  final int page;
  final int total;

  UserPage({required this.users, required this.page, required this.total});

  factory UserPage.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    final userList = (map['data'] as List)
        .map((item) => User.fromJson(item))
        .toList();
    final pagination = map['pagination'] as Map<String, dynamic>;

    return UserPage(
      users: userList,
      page: pagination['page'] as int,
      total: pagination['total'] as int,
    );
  }
}

// Consuming the paginated response
final UserPage page = await api.getAs<UserPage>(
  '/users?page=1',
  fromJson: UserPage.fromJson,
);
```

---

## Direct Dio Escape Hatch

Dio Bolt never hides Dio. You can access the underlying `Dio` client at any time:

```dart
final rawDio = api.dio;
```

---

## Architecture Principles

1. **Dio remains first-class**: Direct access to `dioBolt.dio` for full control.
2. **Two-tier API**: Complete raw control with `DioBoltResponse` + ergonomic `getAs<T>()` model conversion.
3. **No backend schema assumptions**: `dio_bolt` never assumes `{"data": ...}` or `{"success": ...}` formats.
4. **Pure Dart**: Zero UI or Flutter framework dependencies.
5. **Zero state management coupling**: Independent of Bloc, Riverpod, Provider, etc.
6. **Unopinionated storage**: Auth storage provided via interfaces/callbacks.
7. **No code generation required**: Pure Dart models and conversion functions.

---

## Roadmap

- [x] **Phase 1**: Core DioBolt facade
- [x] **Phase 2**: Two-level API (Raw `DioBoltResponse` + Typed `getAs<T>`)
- [ ] **Phase 3**: ApiException and error normalization
- [ ] **Phase 4**: Auth + concurrent 401 refresh handling
- [ ] **Phase 5**: Retry policies + idempotency
- [ ] **Phase 6**: Sanitized production logging
- [ ] **Phase 7**: Upload / download progress tracking
- [ ] **Phase 8**: End-to-end integration tests
- [ ] **Phase 9**: Example application
- [ ] **Phase 10**: Pub.dev polish & documentation

---

## License

MIT License - see [LICENSE](LICENSE) for details.