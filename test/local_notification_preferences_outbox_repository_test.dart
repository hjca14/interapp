import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_notification_preferences_outbox_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/notification_preferences_outbox_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalNotificationPreferencesOutboxRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = LocalNotificationPreferencesOutboxRepository();
  });

  test('read returns null when nothing was written', () async {
    expect(await repository.read('user-1', 'device-1'), isNull);
  });

  test(
    'write then read round-trips the editable values and timestamp',
    () async {
      final schedule = QuietSchedule(
        enabled: true,
        timezone: 'America/Recife',
        days: const {1, 3, 5},
        startTime: ClockTime(hour: 22, minute: 30),
        endTime: ClockTime(hour: 6, minute: 15),
        behavior: QuietScheduleBehavior.blockAll,
      );
      final entry = NotificationPreferencesOutboxEntry(
        pendingDraft: DeviceNotificationPreferences(
          alertMode: AlertMode.notificationOnly,
          quietSchedule: schedule,
        ),
        baselineUpdatedAt: DateTime.utc(2026, 8, 27, 10, 30),
      );

      await repository.write('user-1', 'device-1', entry);
      final read = await repository.read('user-1', 'device-1');

      expect(read, isNotNull);
      expect(read!.pendingDraft.alertMode, AlertMode.notificationOnly);
      expect(read.pendingDraft.quietSchedule, schedule);
      expect(read.baselineUpdatedAt, DateTime.utc(2026, 8, 27, 10, 30));
    },
  );

  test('a null baselineUpdatedAt round-trips as null', () async {
    await repository.write(
      'user-1',
      'device-1',
      NotificationPreferencesOutboxEntry(
        pendingDraft: DeviceNotificationPreferences(),
        baselineUpdatedAt: null,
      ),
    );
    final read = await repository.read('user-1', 'device-1');
    expect(read!.baselineUpdatedAt, isNull);
  });

  test('clear removes the entry', () async {
    await repository.write(
      'user-1',
      'device-1',
      NotificationPreferencesOutboxEntry(
        pendingDraft: DeviceNotificationPreferences(),
        baselineUpdatedAt: null,
      ),
    );
    await repository.clear('user-1', 'device-1');
    expect(await repository.read('user-1', 'device-1'), isNull);
  });

  test('clearing an already-empty entry is a harmless no-op', () async {
    await repository.clear('user-1', 'device-1');
    expect(await repository.read('user-1', 'device-1'), isNull);
  });

  group('isolation by user and device', () {
    test('entries for different users on the same device never mix', () async {
      await repository.write(
        'user-a',
        'device-1',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(
            alertMode: AlertMode.none,
          ),
          baselineUpdatedAt: null,
        ),
      );
      await repository.write(
        'user-b',
        'device-1',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(
            alertMode: AlertMode.ringOnly,
          ),
          baselineUpdatedAt: null,
        ),
      );

      final a = await repository.read('user-a', 'device-1');
      final b = await repository.read('user-b', 'device-1');
      expect(a!.pendingDraft.alertMode, AlertMode.none);
      expect(b!.pendingDraft.alertMode, AlertMode.ringOnly);
    });

    test('entries for the same user on different devices never mix', () async {
      await repository.write(
        'user-1',
        'device-a',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(
            alertMode: AlertMode.none,
          ),
          baselineUpdatedAt: null,
        ),
      );
      await repository.write(
        'user-1',
        'device-b',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(
            alertMode: AlertMode.ringOnly,
          ),
          baselineUpdatedAt: null,
        ),
      );

      final a = await repository.read('user-1', 'device-a');
      final b = await repository.read('user-1', 'device-b');
      expect(a!.pendingDraft.alertMode, AlertMode.none);
      expect(b!.pendingDraft.alertMode, AlertMode.ringOnly);
    });

    test('clearing one entry never affects another user/device pair', () async {
      await repository.write(
        'user-a',
        'device-1',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(),
          baselineUpdatedAt: null,
        ),
      );
      await repository.write(
        'user-b',
        'device-1',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(),
          baselineUpdatedAt: null,
        ),
      );

      await repository.clear('user-a', 'device-1');
      expect(await repository.read('user-a', 'device-1'), isNull);
      expect(await repository.read('user-b', 'device-1'), isNotNull);
    });
  });

  group('safe handling of invalid or unversioned local data', () {
    Future<void> seedRaw(String userId, String deviceId, String raw) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'notification_preferences_outbox_${userId}_$deviceId',
        raw,
      );
    }

    test('malformed JSON is discarded, not applied', () async {
      await seedRaw('user-1', 'device-1', 'not json at all {{{');
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('a JSON value that is not an object is discarded', () async {
      await seedRaw('user-1', 'device-1', jsonEncode([1, 2, 3]));
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('an unknown format version is never applied', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'formatVersion': 999,
          'alertMode': 'none',
          'quietSchedule': {
            'enabled': false,
            'timezone': null,
            'days': <int>[],
            'startTime': null,
            'endTime': null,
            'behavior': 'notificationOnly',
          },
          'baselineUpdatedAt': null,
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('a missing formatVersion is never applied', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'alertMode': 'none',
          'quietSchedule': {
            'enabled': false,
            'timezone': null,
            'days': <int>[],
            'startTime': null,
            'endTime': null,
            'behavior': 'notificationOnly',
          },
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('an unrecognized alertMode is discarded', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'formatVersion': 1,
          'alertMode': 'NOT_A_REAL_MODE',
          'quietSchedule': {
            'enabled': false,
            'timezone': null,
            'days': <int>[],
            'startTime': null,
            'endTime': null,
            'behavior': 'notificationOnly',
          },
          'baselineUpdatedAt': null,
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('an invalid day outside 1..7 is discarded', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'formatVersion': 1,
          'alertMode': 'none',
          'quietSchedule': {
            'enabled': true,
            'timezone': 'America/Recife',
            'days': [0, 8],
            'startTime': '22:00',
            'endTime': '07:00',
            'behavior': 'notificationOnly',
          },
          'baselineUpdatedAt': null,
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('a malformed time string is discarded', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'formatVersion': 1,
          'alertMode': 'none',
          'quietSchedule': {
            'enabled': true,
            'timezone': 'America/Recife',
            'days': [1],
            'startTime': 'not-a-time',
            'endTime': '07:00',
            'behavior': 'notificationOnly',
          },
          'baselineUpdatedAt': null,
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });

    test('a malformed baselineUpdatedAt is discarded', () async {
      await seedRaw(
        'user-1',
        'device-1',
        jsonEncode({
          'formatVersion': 1,
          'alertMode': 'none',
          'quietSchedule': {
            'enabled': false,
            'timezone': null,
            'days': <int>[],
            'startTime': null,
            'endTime': null,
            'behavior': 'notificationOnly',
          },
          'baselineUpdatedAt': 'not-a-date',
        }),
      );
      expect(await repository.read('user-1', 'device-1'), isNull);
    });
  });

  test(
    'the persisted payload never contains a token, e-mail, or password',
    () async {
      await repository.write(
        'user-1',
        'device-1',
        NotificationPreferencesOutboxEntry(
          pendingDraft: DeviceNotificationPreferences(
            alertMode: AlertMode.ringOnly,
          ),
          baselineUpdatedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(
        'notification_preferences_outbox_user-1_device-1',
      )!;
      for (final forbidden in [
        'token',
        'password',
        'senha',
        'email',
        '@',
        'Bearer',
      ]) {
        expect(raw.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
      }
    },
  );
}
