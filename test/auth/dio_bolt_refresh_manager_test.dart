import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dio_bolt/dio_bolt.dart';
import 'package:dio_bolt/src/auth/dio_bolt_auth_interceptor.dart';
import 'package:dio_bolt/src/auth/dio_bolt_refresh_manager.dart';
import 'package:test/test.dart';

void main() {
  group('DioBoltRefreshManager - Unit Tests', () {
    test('single-flight executes refreshToken callback exactly once for concurrent requests', () async {
      int refreshCallCount = 0;
      final completer = Completer<String?>();

      final manager = DioBoltRefreshManager(
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) {
            refreshCallCount++;
            return completer.future;
          },
        ),
        refreshClient: Dio(),
      );

      final dummy401 = const DioBoltResponse(
        isSuccess: false,
        statusCode: 401,
        message: 'Unauthorized',
      );

      // Trigger 5 concurrent refresh calls
      final futures = List.generate(5, (_) => manager.refreshToken(dummy401));

      expect(refreshCallCount, equals(1)); // Only one underlying invocation

      completer.complete('refreshed-token');
      final results = await Future.wait(futures);

      expect(results, equals(List.filled(5, 'refreshed-token')));
    });

    test('persistence failure treats refresh as failed and triggers onRefreshFailed exactly once', () async {
      int onRefreshFailedCalls = 0;
      DioBoltResponse? capturedFailure;

      final manager = DioBoltRefreshManager(
        auth: DioBoltAuth(
          getAccessToken: () => 'token',
          refreshToken: (_) => 'new-token',
          onTokenRefreshed: (_) => throw Exception('Disk full error'),
          onRefreshFailed: (resp) {
            onRefreshFailedCalls++;
            capturedFailure = resp;
          },
        ),
        refreshClient: Dio(),
      );

      final dummy401 = const DioBoltResponse(
        isSuccess: false,
        statusCode: 401,
        message: 'Unauthorized',
      );

      final result = await manager.refreshToken(dummy401);

      expect(result, isNull);
      expect(onRefreshFailedCalls, equals(1));
      expect(capturedFailure?.statusCode, equals(401));
    });

    test('fromDio creates isolated Dio client without recursive interceptors', () {
      final mainDio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      final customInterceptor = InterceptorsWrapper(
        onRequest: (opt, handler) => handler.next(opt),
      );
      mainDio.interceptors.add(customInterceptor);

      final manager = DioBoltRefreshManager.fromDio(
        auth: DioBoltAuth(
          getAccessToken: () => 't',
          refreshToken: (_) => 't',
        ),
        mainDio: mainDio,
      );

      expect(manager.refreshClient.options.baseUrl, equals('https://api.example.com'));
      expect(manager.refreshClient.interceptors.whereType<DioBoltAuthInterceptor>(), isEmpty);
      expect(manager.refreshClient.interceptors.contains(customInterceptor), isFalse);
      expect(manager.refreshClient, isNot(same(mainDio)));
    });
  });
}
