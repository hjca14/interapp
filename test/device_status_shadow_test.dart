import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';

void main() {
  group('DeviceStatus.fromReportedShadow', () {
    test('parses every field from the protocol\'s reported-shadow example', () {
      final status = DeviceStatus.fromReportedShadow(const {
        'firmware_version': '0.1.0',
        'hardware_version': '1.0',
        'intercom_state': 'IDLE',
        'wifi_rssi': -54,
        'uptime_ms': 3812000,
        'provisioned': true,
        'health_interval_s':
            3600, // hardware-config field: must be ignored here
      }, isOnline: true);

      expect(status.isOnline, isTrue);
      expect(status.firmwareVersion, '0.1.0');
      expect(status.hardwareVersion, '1.0');
      expect(status.intercomState, IntercomState.idle);
      expect(status.wifiRssi, -54);
      expect(status.uptime, const Duration(milliseconds: 3812000));
      expect(status.isProvisioned, isTrue);
    });

    test(
      'isOnline and lastSeen come from the caller, never from the shadow map',
      () {
        final status = DeviceStatus.fromReportedShadow(const {
          'intercom_state': 'IDLE',
        }, isOnline: false);

        expect(status.isOnline, isFalse);
        expect(status.lastSeen, isNull);
      },
    );

    test('tolerates missing fields without throwing', () {
      final status = DeviceStatus.fromReportedShadow(const {}, isOnline: false);

      expect(status.firmwareVersion, isNull);
      expect(status.intercomState, IntercomState.unreported);
      expect(status.wifiRssi, isNull);
      expect(status.uptime, isNull);
      expect(status.isProvisioned, isNull);
    });

    test('tolerates unknown extra fields without throwing', () {
      final status = DeviceStatus.fromReportedShadow(const {
        'intercom_state': 'IDLE',
        'some_future_field': 'value',
        'nested': <String, dynamic>{},
      }, isOnline: true);

      expect(status.intercomState, IntercomState.idle);
    });

    test('an unrecognized intercom_state is preserved, not dropped', () {
      final status = DeviceStatus.fromReportedShadow(const {
        'intercom_state': 'SOME_FUTURE_STATE',
      }, isOnline: true);

      expect(status.intercomState.raw, 'SOME_FUTURE_STATE');
      expect(status.intercomState, isNot(IntercomState.idle));
    });
  });
}
