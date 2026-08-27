import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';

void main() {
  test('defaults and serialization contain only local door preferences', () {
    const settings = DeviceSettings();
    expect(settings.confirmBeforeOpeningDoor, isTrue);
    expect(settings.requireDeviceAuthenticationToOpenDoor, isFalse);
    expect(settings.toMap().keys, {
      'confirmBeforeOpeningDoor',
      'requireDeviceAuthenticationToOpenDoor',
    });
  });

  test('legacy notification fields are ignored while door values survive', () {
    final settings = DeviceSettings.fromMap({
      'calls': {'localNetworkAlertMode': 'none'},
      'quietHours': {'enabled': true},
      'confirmBeforeOpeningDoor': false,
      'requireDeviceAuthenticationToOpenDoor': true,
    });
    expect(settings.confirmBeforeOpeningDoor, isFalse);
    expect(settings.requireDeviceAuthenticationToOpenDoor, isTrue);
    expect(settings.toMap(), isNot(contains('calls')));
    expect(settings.toMap(), isNot(contains('quietHours')));
  });

  test('local repository remains isolated by device', () async {
    SharedPreferences.setMockInitialValues({
      'device_settings_a': jsonEncode({
        'calls': {'remoteNetworkAlertMode': 'none'},
        'confirmBeforeOpeningDoor': false,
      }),
    });
    final repository = LocalDeviceSettingsRepository();
    expect((await repository.get('a')).confirmBeforeOpeningDoor, isFalse);
    expect((await repository.get('b')).confirmBeforeOpeningDoor, isTrue);
  });
}
