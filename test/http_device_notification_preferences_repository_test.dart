import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/devices/data/repositories/http_device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';

Map<String, dynamic> response({
  String alertMode = 'RING_AND_NOTIFICATION',
  String? updatedAt,
}) => {
  'version': 1,
  'alert_mode': alertMode,
  'quiet_schedule': {
    'enabled': false,
    'timezone': null,
    'days': <int>[],
    'start_time': null,
    'end_time': null,
    'behavior': 'NOTIFICATION_ONLY',
  },
  'updated_at': updatedAt,
};

void main() {
  test('GET uses escaped device path and parses complete response', () async {
    String? path;
    final repository = HttpDeviceNotificationPreferencesRepository.forTest(
      get: (value) async {
        path = value;
        return response();
      },
      patch: (_, {required body}) async => response(),
    );

    final result = await repository.get('bridge/a b');

    expect(
      path,
      '/v1/devices/bridge%2Fa%20b/notification-preferences',
    );
    expect(result.alertMode, AlertMode.ringAndNotification);
  });

  test('PATCH sends only changed editable fields and returns server value', () async {
    String? path;
    Map<String, dynamic>? payload;
    var calls = 0;
    final repository = HttpDeviceNotificationPreferencesRepository.forTest(
      get: (_) async => response(),
      patch: (value, {required body}) async {
        calls++;
        path = value;
        payload = body;
        return response(
          alertMode: 'NONE',
          updatedAt: '2026-08-27T10:00:00Z',
        );
      },
    );
    final baseline = DeviceNotificationPreferences();

    final confirmed = await repository.patch(
      'device',
      baseline,
      baseline.copyWith(alertMode: AlertMode.none),
    );

    expect(calls, 1);
    expect(path, '/v1/devices/device/notification-preferences');
    expect(payload, {'alert_mode': 'NONE'});
    expect(confirmed.alertMode, AlertMode.none);
    expect(confirmed.updatedAt, DateTime.utc(2026, 8, 27, 10));
  });

  test('nested PATCH orders days and omits unrelated values', () async {
    Map<String, dynamic>? payload;
    final repository = HttpDeviceNotificationPreferencesRepository.forTest(
      get: (_) async => response(),
      patch: (_, {required body}) async {
        payload = body;
        return {
          ...response(),
          'quiet_schedule': {
            'enabled': true,
            'timezone': 'America/Recife',
            'days': [1, 3, 7],
            'start_time': '22:00',
            'end_time': '07:00',
            'behavior': 'BLOCK_ALL',
          },
        };
      },
    );
    final baseline = DeviceNotificationPreferences();
    final draft = baseline.copyWith(
      quietSchedule: QuietSchedule(
        enabled: true,
        timezone: 'America/Recife',
        days: const {7, 1, 3},
        startTime: ClockTime(hour: 22, minute: 0),
        endTime: ClockTime(hour: 7, minute: 0),
        behavior: QuietScheduleBehavior.blockAll,
      ),
    );

    await repository.patch('device', baseline, draft);

    expect(payload!['quiet_schedule'], {
      'enabled': true,
      'timezone': 'America/Recife',
      'days': [1, 3, 7],
      'start_time': '22:00',
      'end_time': '07:00',
      'behavior': 'BLOCK_ALL',
    });
    expect(payload.toString(), isNot(contains('version')));
    expect(payload.toString(), isNot(contains('user_id')));
    expect(payload.toString(), isNot(contains('confirmBeforeOpeningDoor')));
  });

  test('identical or read-only-only differences never PATCH', () async {
    var calls = 0;
    final repository = HttpDeviceNotificationPreferencesRepository.forTest(
      get: (_) async => response(),
      patch: (_, {required body}) async {
        calls++;
        return response();
      },
    );
    final baseline = DeviceNotificationPreferences(
      updatedAt: DateTime.utc(2026, 8, 27),
    );

    expect(await repository.patch('device', baseline, baseline), same(baseline));
    expect(
      await repository.patch(
        'device',
        baseline,
        baseline.copyWith(updatedAt: DateTime.utc(2026, 8, 28)),
      ),
      same(baseline),
    );
    expect(
      await repository.patch('device', baseline, baseline.copyWith(version: 2)),
      same(baseline),
    );
    expect(calls, 0);
  });

  group('authenticated HTTP failures', () {
    final cases = {
      400: ApiFailureKind.badRequest,
      404: ApiFailureKind.notFound,
      409: ApiFailureKind.conflict,
      413: ApiFailureKind.payloadTooLarge,
      500: ApiFailureKind.server,
      503: ApiFailureKind.unavailable,
    };
    for (final entry in cases.entries) {
      test('sanitizes HTTP ${entry.key}', () async {
        final repository = liveRepository(
          MockClient(
            (_) async => http.Response(
              'sensitive backend payload',
              entry.key,
              headers: {'x-request-id': 'support-id'},
            ),
          ),
        );
        await expectLater(
          repository.get('device'),
          throwsA(
            isA<ApiFailure>()
                .having((failure) => failure.kind, 'kind', entry.value)
                .having(
                  (failure) => failure.message,
                  'message',
                  isNot(contains('sensitive')),
                )
                .having(
                  (failure) => failure.requestId,
                  'requestId',
                  'support-id',
                ),
          ),
        );
      });
    }

    test('401 retries once then invalidates session', () async {
      var requests = 0;
      final auth = LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true),
      );
      final repository = liveRepository(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 401);
        }),
        auth: auth,
      );

      await expectLater(
        repository.get('device'),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.unauthorized,
          ),
        ),
      );
      expect(requests, 2);
      expect((await auth.currentSession).isSignedIn, isFalse);
    });

    test('timeout and offline remain sanitized typed failures', () async {
      final timeoutRepository = liveRepository(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(jsonEncode(response()), 200);
        }),
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        timeoutRepository.get('device'),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      final offlineRepository = liveRepository(
        MockClient((_) async => throw http.ClientException('secret')),
      );
      await expectLater(
        offlineRepository.get('device'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.offline,
              )
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains('secret')),
              ),
        ),
      );
    });

    test('incompatible successful response is sanitized', () async {
      final repository = liveRepository(
        MockClient((_) async => http.Response('{"unexpected":true}', 200)),
      );
      await expectLater(
        repository.get('device'),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    });
  });
}

HttpDeviceNotificationPreferencesRepository liveRepository(
  http.Client client, {
  LocalAuthRepository? auth,
  Duration timeout = const Duration(seconds: 1),
}) {
  return HttpDeviceNotificationPreferencesRepository(
    InterBridgeApiClient(
      baseUrl: 'https://api.example.invalid',
      auth:
          auth ??
          LocalAuthRepository(
            initial: const AuthSession(isSignedIn: true),
          ),
      client: client,
      timeout: timeout,
    ),
  );
}
