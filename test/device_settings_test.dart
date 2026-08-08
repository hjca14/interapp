import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CallAlertMode', () {
    test('from() combines ring/notification flags into the right mode', () {
      expect(CallAlertMode.from(ring: false, notification: false), CallAlertMode.none);
      expect(CallAlertMode.from(ring: true, notification: false), CallAlertMode.ringOnly);
      expect(CallAlertMode.from(ring: false, notification: true), CallAlertMode.notificationOnly);
      expect(CallAlertMode.from(ring: true, notification: true), CallAlertMode.ringAndNotification);
    });

    test('includesRing/includesNotification reflect the mode', () {
      expect(CallAlertMode.none.includesRing, isFalse);
      expect(CallAlertMode.none.includesNotification, isFalse);
      expect(CallAlertMode.ringOnly.includesRing, isTrue);
      expect(CallAlertMode.ringOnly.includesNotification, isFalse);
      expect(CallAlertMode.notificationOnly.includesRing, isFalse);
      expect(CallAlertMode.notificationOnly.includesNotification, isTrue);
      expect(CallAlertMode.ringAndNotification.includesRing, isTrue);
      expect(CallAlertMode.ringAndNotification.includesNotification, isTrue);
    });
  });

  group('DeviceSettings defaults', () {
    test('sensible values out of the box', () {
      const settings = DeviceSettings();
      expect(settings.calls.localNetworkAlertMode, CallAlertMode.ringAndNotification);
      expect(settings.calls.remoteNetworkAlertMode, CallAlertMode.notificationOnly);
      expect(settings.quietHours.enabled, isFalse);
      expect(settings.quietHours.start.hour, 22);
      expect(settings.quietHours.end.hour, 7);
      expect(settings.quietHours.weekdays, {1, 2, 3, 4, 5, 6, 7});
      expect(settings.quietHours.behavior, QuietHoursBehavior.blockAll);
      expect(settings.confirmBeforeOpeningDoor, isTrue);
      expect(settings.requireDeviceAuthenticationToOpenDoor, isFalse);
    });
  });

  group('DeviceSettings serialization', () {
    test('toMap/fromMap round-trips every field, including edits', () {
      const original = DeviceSettings(
        calls: DeviceCallSettings(
          localNetworkAlertMode: CallAlertMode.ringOnly,
          remoteNetworkAlertMode: CallAlertMode.none,
        ),
        quietHours: QuietHoursSettings(
          enabled: true,
          start: ClockTime(hour: 23, minute: 30),
          end: ClockTime(hour: 6, minute: 15),
          weekdays: {6, 7},
          behavior: QuietHoursBehavior.silentNotificationOnly,
        ),
        confirmBeforeOpeningDoor: false,
        requireDeviceAuthenticationToOpenDoor: true,
      );

      final decoded = DeviceSettings.fromMap(original.toMap());

      expect(decoded.calls.localNetworkAlertMode, CallAlertMode.ringOnly);
      expect(decoded.calls.remoteNetworkAlertMode, CallAlertMode.none);
      expect(decoded.quietHours.enabled, isTrue);
      expect(decoded.quietHours.start.hour, 23);
      expect(decoded.quietHours.start.minute, 30);
      expect(decoded.quietHours.end.hour, 6);
      expect(decoded.quietHours.end.minute, 15);
      expect(decoded.quietHours.weekdays, {6, 7});
      expect(decoded.quietHours.behavior, QuietHoursBehavior.silentNotificationOnly);
      expect(decoded.confirmBeforeOpeningDoor, isFalse);
      expect(decoded.requireDeviceAuthenticationToOpenDoor, isTrue);
    });

    test('fromMap falls back to defaults for missing/malformed fields', () {
      final decoded = DeviceSettings.fromMap(const {'confirmBeforeOpeningDoor': false});

      expect(decoded.calls.localNetworkAlertMode, CallAlertMode.ringAndNotification);
      expect(decoded.quietHours.enabled, isFalse);
      expect(decoded.confirmBeforeOpeningDoor, isFalse);
      expect(decoded.requireDeviceAuthenticationToOpenDoor, isFalse);
    });
  });

  group('LocalDeviceSettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('get() returns defaults when nothing was saved yet', () async {
      final repository = LocalDeviceSettingsRepository();

      final settings = await repository.get('device-1');

      expect(settings.calls.localNetworkAlertMode, CallAlertMode.ringAndNotification);
      expect(settings.confirmBeforeOpeningDoor, isTrue);
    });

    test('save() then get() round-trips through real persistence', () async {
      final repository = LocalDeviceSettingsRepository();
      const updated = DeviceSettings(
        confirmBeforeOpeningDoor: false,
        requireDeviceAuthenticationToOpenDoor: true,
      );

      await repository.save('device-1', updated);
      final reloaded = await repository.get('device-1');

      expect(reloaded.confirmBeforeOpeningDoor, isFalse);
      expect(reloaded.requireDeviceAuthenticationToOpenDoor, isTrue);
    });

    test('settings are isolated per deviceId', () async {
      final repository = LocalDeviceSettingsRepository();
      await repository.save('device-a', const DeviceSettings(confirmBeforeOpeningDoor: false));
      await repository.save('device-b', const DeviceSettings(confirmBeforeOpeningDoor: true));

      final settingsA = await repository.get('device-a');
      final settingsB = await repository.get('device-b');

      expect(settingsA.confirmBeforeOpeningDoor, isFalse);
      expect(settingsB.confirmBeforeOpeningDoor, isTrue);
    });

    test('a later save() overwrites the previous value for the same device', () async {
      final repository = LocalDeviceSettingsRepository();
      await repository.save('device-1', const DeviceSettings(confirmBeforeOpeningDoor: true));
      await repository.save('device-1', const DeviceSettings(confirmBeforeOpeningDoor: false));

      final settings = await repository.get('device-1');

      expect(settings.confirmBeforeOpeningDoor, isFalse);
    });
  });
}
