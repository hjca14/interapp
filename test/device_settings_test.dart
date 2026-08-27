import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_hardware_config.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults and serialization contain only local door preferences', () {
    const settings = DeviceSettings();
    expect(settings.confirmBeforeOpeningDoor, isTrue);
    expect(settings.requireDeviceAuthenticationToOpenDoor, isFalse);
    expect(settings.toMap().keys, {
      'confirmBeforeOpeningDoor',
      'requireDeviceAuthenticationToOpenDoor',
    });
  });

  test('DeviceSettings stays separate from hardware shadow configuration', () {
    const settings = DeviceSettings();
    const hardware = DeviceHardwareConfig();
    expect(settings, isNot(isA<DeviceHardwareConfig>()));
    expect(hardware, isNot(isA<DeviceSettings>()));
    expect(
      settings.toMap().keys,
      isNot(containsAll(['health_interval_s', 'ring_timeout_ms'])),
    );
  });

  test('legacy notification fields are ignored while door values survive', () {
    final settings = DeviceSettings.fromMap({
      'calls': {'localNetworkAlertMode': 'none'},
      'quietHours': {'enabled': true},
      'unknown': 42,
      'confirmBeforeOpeningDoor': false,
      'requireDeviceAuthenticationToOpenDoor': true,
    });
    expect(settings.confirmBeforeOpeningDoor, isFalse);
    expect(settings.requireDeviceAuthenticationToOpenDoor, isTrue);
    expect(settings.toMap(), isNot(contains('calls')));
    expect(settings.toMap(), isNot(contains('quietHours')));
  });

  test('malformed field types fall back independently', () {
    final settings = DeviceSettings.fromMap({
      'confirmBeforeOpeningDoor': 'false',
      'requireDeviceAuthenticationToOpenDoor': 1,
    });
    expect(settings.confirmBeforeOpeningDoor, isTrue);
    expect(settings.requireDeviceAuthenticationToOpenDoor, isFalse);
  });

  test(
    'repository safely defaults corrupted and foreign JSON values',
    () async {
      for (final raw in ['{', '[]', '"text"', '42', 'true']) {
        SharedPreferences.setMockInitialValues({'device_settings_a': raw});
        final settings = await LocalDeviceSettingsRepository().get('a');
        expect(settings.confirmBeforeOpeningDoor, isTrue, reason: raw);
        expect(
          settings.requireDeviceAuthenticationToOpenDoor,
          isFalse,
          reason: raw,
        );
      }
    },
  );

  test(
    'local repository save, overwrite and isolation work by device',
    () async {
      final repository = LocalDeviceSettingsRepository();
      await repository.save(
        'a',
        const DeviceSettings(confirmBeforeOpeningDoor: false),
      );
      expect((await repository.get('a')).confirmBeforeOpeningDoor, isFalse);
      expect((await repository.get('b')).confirmBeforeOpeningDoor, isTrue);

      await repository.save(
        'a',
        const DeviceSettings(requireDeviceAuthenticationToOpenDoor: true),
      );
      final overwritten = await repository.get('a');
      expect(overwritten.confirmBeforeOpeningDoor, isTrue);
      expect(overwritten.requireDeviceAuthenticationToOpenDoor, isTrue);
    },
  );

  test(
    'repository reads legacy object and never reserializes legacy keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'device_settings_a': jsonEncode({
          'calls': {'remoteNetworkAlertMode': 'none'},
          'quietHours': {'enabled': true},
          'confirmBeforeOpeningDoor': false,
        }),
      });
      final repository = LocalDeviceSettingsRepository();
      final settings = await repository.get('a');
      await repository.save('a', settings);
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString('device_settings_a')!;
      expect(stored, isNot(contains('calls')));
      expect(stored, isNot(contains('quietHours')));
      expect(settings.confirmBeforeOpeningDoor, isFalse);
    },
  );
}
