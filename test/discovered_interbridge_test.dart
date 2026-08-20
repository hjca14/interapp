import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';

void main() {
  group('friendlyInterBridgeName', () {
    test('derives a friendly name from the last 4 hex chars of device_id', () {
      expect(
        friendlyInterBridgeName('ib-7f3a91c2d84e4fa9b621b88658fdca77'),
        'InterBridge-CA77',
      );
    });

    test('uppercases the suffix', () {
      expect(
        friendlyInterBridgeName('ib-000000000000000000000000000000a91c'),
        'InterBridge-A91C',
      );
    });
  });

  group('DiscoveredInterBridge equality', () {
    test(
      'two instances with the same deviceId are equal, even with different names',
      () {
        const a = DiscoveredInterBridge(
          deviceId: 'ib-1',
          friendlyName: 'InterBridge-AAAA',
        );
        const b = DiscoveredInterBridge(
          deviceId: 'ib-1',
          friendlyName: 'InterBridge-BBBB',
        );

        expect(a, b);
      },
    );

    test('different deviceId means different device', () {
      const a = DiscoveredInterBridge(
        deviceId: 'ib-1',
        friendlyName: 'InterBridge-AAAA',
      );
      const b = DiscoveredInterBridge(
        deviceId: 'ib-2',
        friendlyName: 'InterBridge-AAAA',
      );

      expect(a, isNot(b));
    });
  });
}
