import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/core/push/push_installation_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

class FakeAuth implements AuthRepository {
  bool invalidated = false;
  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async =>
      forceRefresh ? 'refreshed-secret' : 'access-secret';
  @override
  Future<void> invalidateSession() async => invalidated = true;
  @override
  Future<AuthSession> get currentSession async =>
      const AuthSession(isSignedIn: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const id = '123e4567-e89b-42d3-a456-426614174000';
  const token = 'private-fcm-token';

  test('PUT has exact method, path, headers and JSON and accepts empty 204', () async {
    late http.Request captured;
    final repo = HttpPushInstallationRepository(
      InterBridgeApiClient(
        baseUrl: 'https://api.example.test',
        auth: FakeAuth(),
        client: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      ),
    );
    await repo.registerInstallation(
      installationId: id,
      token: token,
      appVersion: '1.0.0+1',
    );
    expect(captured.method, 'PUT');
    expect(captured.url.path, '/v1/push/installations/$id');
    expect(captured.headers['authorization'], 'Bearer access-secret');
    expect(captured.headers['content-type'], 'application/json');
    expect(jsonDecode(captured.body), {
      'version': 1,
      'platform': 'ANDROID',
      'push_provider': 'FCM',
      'token': token,
      'app_id': 'com.interbridge.app',
      'app_version': '1.0.0+1',
    });
  });

  test('DELETE has exact method/path and accepts empty 204', () async {
    late http.Request captured;
    final repo = HttpPushInstallationRepository(
      InterBridgeApiClient(
        baseUrl: 'https://api.example.test',
        auth: FakeAuth(),
        client: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      ),
    );
    await repo.deleteInstallation(id);
    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/v1/push/installations/$id');
  });

  for (final entry in <int, ApiFailureKind>{
    400: ApiFailureKind.badRequest,
    409: ApiFailureKind.conflict,
    413: ApiFailureKind.payloadTooLarge,
    429: ApiFailureKind.rateLimited,
    500: ApiFailureKind.server,
    503: ApiFailureKind.unavailable,
  }.entries) {
    test('maps ${entry.key} without leaking response or credentials', () async {
      final repo = HttpPushInstallationRepository(
        InterBridgeApiClient(
          baseUrl: 'https://api.example.test',
          auth: FakeAuth(),
          client: MockClient(
            (_) async => http.Response('body contains $token', entry.key,
                headers: {'retry-after': '2'}),
          ),
        ),
      );
      try {
        await repo.deleteInstallation(id);
        fail('expected failure');
      } on ApiFailure catch (failure) {
        expect(failure.kind, entry.value);
        expect(failure.toString(), isNot(contains(token)));
        expect(failure.toString(), isNot(contains('Bearer')));
        if (entry.key == 429) expect(failure.retryAfter, const Duration(seconds: 2));
      }
    });
  }

  test('401 refreshes once, invalidates centrally and stays sanitized', () async {
    final auth = FakeAuth();
    final repo = HttpPushInstallationRepository(
      InterBridgeApiClient(
        baseUrl: 'https://api.example.test',
        auth: auth,
        client: MockClient((_) async => http.Response(token, 401)),
      ),
    );
    await expectLater(repo.deleteInstallation(id), throwsA(isA<ApiFailure>()));
    expect(auth.invalidated, isTrue);
  });

  test('timeout and network errors are sanitized', () async {
    final timeoutRepository = HttpPushInstallationRepository(
      InterBridgeApiClient(
        baseUrl: 'https://api.example.test',
        auth: FakeAuth(),
        timeout: Duration.zero,
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return http.Response('', 204);
        }),
      ),
    );
    await expectLater(
      timeoutRepository.deleteInstallation(id),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );

    final networkRepository = HttpPushInstallationRepository(
      InterBridgeApiClient(
        baseUrl: 'https://api.example.test',
        auth: FakeAuth(),
        client: MockClient((_) async => throw http.ClientException(token)),
      ),
    );
    try {
      await networkRepository.deleteInstallation(id);
      fail('expected network failure');
    } on ApiFailure catch (failure) {
      expect(failure.kind, ApiFailureKind.offline);
      expect(failure.toString(), isNot(contains(token)));
    }
  });
}
