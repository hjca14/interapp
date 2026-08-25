import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/devices/data/parsers/device_api_parser.dart';
import 'package:interapp/features/devices/data/repositories/http_device_repository.dart';

void main() {
  test('sends bearer access token and preserves opaque cursor', () async {
    final auth = LocalAuthRepository(
      initial: const AuthSession(isSignedIn: true, userId: 'opaque'),
    );
    final httpClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-access-token');
      expect(request.headers['Accept'], 'application/json');
      return http.Response(
        jsonEncode({
          'items': [
            {
              'device_id': 'device-placeholder',
              'display_name': null,
              'role': 'OWNER',
              'status': 'ACTIVE',
            },
          ],
          'next_cursor': 'opaque+/=',
        }),
        200,
      );
    });
    final repository = _createRepository(auth, httpClient);

    final page = await repository.listDevices();

    expect(page.nextCursor, 'opaque+/=');
    expect(page.items.single.displayName, isNull);
  });

  test('updateDeviceName sends a PATCH with the trimmed name', () async {
    final auth = LocalAuthRepository(
      initial: const AuthSession(isSignedIn: true, userId: 'opaque'),
    );
    http.Request? capturedRequest;
    final httpClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({
          'device_id': 'device-placeholder',
          'display_name': 'Minha casa',
          'hardware_version': null,
          'ownership_status': 'claimed',
          'provisioning_status': 'active',
          'role': 'OWNER',
        }),
        200,
      );
    });
    final repository = _createRepository(auth, httpClient);

    final updated = await repository.updateDeviceName(
      'device-placeholder',
      'Minha casa',
    );

    expect(capturedRequest?.method, 'PATCH');
    expect(capturedRequest?.url.path, '/v1/devices/device-placeholder');
    expect(
      jsonDecode(capturedRequest!.body),
      equals({'display_name': 'Minha casa'}),
    );
    expect(updated.displayName, 'Minha casa');
  });

  test('updateDeviceName sends an explicit null to clear the name', () async {
    final auth = LocalAuthRepository(
      initial: const AuthSession(isSignedIn: true, userId: 'opaque'),
    );
    http.Request? capturedRequest;
    final httpClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({
          'device_id': 'device-placeholder',
          'display_name': null,
          'hardware_version': null,
          'ownership_status': 'claimed',
          'provisioning_status': 'active',
          'role': 'OWNER',
        }),
        200,
      );
    });
    final repository = _createRepository(auth, httpClient);

    final updated = await repository.updateDeviceName(
      'device-placeholder',
      null,
    );

    expect(jsonDecode(capturedRequest!.body), equals({'display_name': null}));
    expect(updated.displayName, isNull);
  });

  test('parser keeps null health without fabricating telemetry', () {
    const parser = DeviceApiParser();

    final status = parser.parseDeviceStatus({
      'device_id': 'placeholder',
      'connectivity': 'UNKNOWN',
      'freshness': 'UNKNOWN',
      'health': null,
    });

    expect(status.health, isNull);
  });

  test('parser rejects invalid health timestamp with typed error', () {
    const parser = DeviceApiParser();

    expect(
      () => parser.parseDeviceStatus({
        'device_id': 'placeholder',
        'connectivity': 'RECENTLY_SEEN',
        'freshness': 'FRESH',
        'health': {
          'intercom_state': 'IDLE',
          'firmware_version': 'placeholder',
          'last_seen_at': 'invalid',
        },
      }),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('parser rejects unknown enums with sanitized typed error', () {
    const parser = DeviceApiParser();

    expect(
      () => parser.parseDeviceStatus({
        'device_id': 'placeholder',
        'connectivity': 'NEW_VALUE',
        'freshness': 'UNKNOWN',
        'health': null,
      }),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('invalid JSON is a typed API failure', () async {
    final auth = LocalAuthRepository(
      initial: const AuthSession(isSignedIn: true),
    );
    final httpClient = MockClient((_) async => http.Response('not-json', 200));
    final repository = _createRepository(auth, httpClient);

    expect(repository.listDevices, throwsA(isA<ApiFailure>()));
  });
}

HttpDeviceRepository _createRepository(
  LocalAuthRepository auth,
  http.Client httpClient,
) {
  return HttpDeviceRepository(
    InterBridgeApiClient(
      baseUrl: 'https://api.example.invalid',
      auth: auth,
      client: httpClient,
    ),
  );
}
