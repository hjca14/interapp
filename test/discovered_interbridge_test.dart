import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';

void main() {
  group('DiscoveredInterBridge equality', () {
    test(
      'same transportId is equal even with different advertised names',
      () {
        const a = DiscoveredInterBridge(
          transportId: 'ble-handle-1',
          friendlyName: 'InterBridge-AAAA',
        );
        const b = DiscoveredInterBridge(
          transportId: 'ble-handle-1',
          friendlyName: 'InterBridge-BBBB',
        );

        expect(a, b);
      },
    );

    test('different transportId means different discovery candidate', () {
      const a = DiscoveredInterBridge(
        transportId: 'ble-handle-1',
        friendlyName: 'InterBridge-AAAA',
      );
      const b = DiscoveredInterBridge(
        transportId: 'ble-handle-2',
        friendlyName: 'InterBridge-AAAA',
      );

      expect(a, isNot(b));
    });
  });
}
