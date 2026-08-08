import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';

void main() {
  group('InterBridgeDevice storage round-trip', () {
    test('toStorage/fromStorage preserves id, name and createdAt', () {
      final device = InterBridgeDevice(
        id: 'abc123',
        name: 'Portaria',
        createdAt: DateTime.utc(2026, 1, 15, 10, 30),
      );

      final decoded = InterBridgeDevice.fromStorage(device.toStorage());

      expect(decoded, isNotNull);
      expect(decoded!.id, device.id);
      expect(decoded.name, device.name);
      expect(decoded.createdAt, device.createdAt);
    });

    test('fromStorage returns null for malformed entries', () {
      expect(InterBridgeDevice.fromStorage(''), isNull);
      expect(InterBridgeDevice.fromStorage('only-one-part'), isNull);
      expect(InterBridgeDevice.fromStorage('id\tname'), isNull);
      expect(InterBridgeDevice.fromStorage('\tname\t2026-01-01T00:00:00.000Z'), isNull);
      expect(InterBridgeDevice.fromStorage('id\t\t2026-01-01T00:00:00.000Z'), isNull);
    });

    test('fromStorage falls back to a valid date instead of throwing on garbage', () {
      final decoded = InterBridgeDevice.fromStorage('id\tname\tnot-a-date');

      expect(decoded, isNotNull);
      expect(decoded!.createdAt, isA<DateTime>());
    });
  });
}
