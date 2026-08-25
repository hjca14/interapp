import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

void main() {
  group('deviceDisplayName', () {
    test('returns the trimmed custom name when present', () {
      expect(deviceDisplayName('  Minha casa  '), 'Minha casa');
    });

    test('falls back to InterBridge when null', () {
      expect(deviceDisplayName(null), 'InterBridge');
    });

    test('falls back to InterBridge for an empty string', () {
      expect(deviceDisplayName(''), 'InterBridge');
    });

    test('falls back to InterBridge for a whitespace-only string', () {
      expect(deviceDisplayName('   '), 'InterBridge');
    });

    test('never returns something resembling a device_id', () {
      // safeName/deviceDisplayName must never be used to smuggle device_id
      // into the UI as a title — this only guards the fallback text itself.
      expect(deviceDisplayName(null), isNot(contains('device')));
    });
  });

  group('ApiDeviceSummary.safeName', () {
    ApiDeviceSummary summary({String? displayName}) => ApiDeviceSummary(
      deviceId: 'ib-00000000000000000000000000000001',
      displayName: displayName,
      role: DeviceRole.owner,
      status: MembershipStatus.active,
    );

    test('shows the display name when set', () {
      expect(summary(displayName: 'Interfone').safeName, 'Interfone');
    });

    test('falls back to InterBridge without exposing device_id', () {
      final name = summary().safeName;
      expect(name, 'InterBridge');
      expect(name, isNot(contains('ib-00000000000000000000000000000001')));
    });
  });
}
