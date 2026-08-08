import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';

void main() {
  group('LocalDeviceConnectionRepository', () {
    test('watchStatus starts every device as not connected', () async {
      final repository = LocalDeviceConnectionRepository();

      final status = await repository.watchStatus('device-1').first;

      expect(status.isOnline, isFalse);
      expect(status.hasIncomingCall, isFalse);
    });

    test('simulateIncomingCall pulses hasIncomingCall for that device', () async {
      final repository = LocalDeviceConnectionRepository();
      final events = <DeviceStatus>[];
      final subscription = repository.watchStatus('device-1').listen(events.add);
      await Future<void>.delayed(Duration.zero);

      repository.simulateIncomingCall('device-1');
      await Future<void>.delayed(Duration.zero);

      expect(events.last.hasIncomingCall, isTrue);
      await subscription.cancel();
    });

    test('simulateIncomingCall on one device does not leak into another', () async {
      final repository = LocalDeviceConnectionRepository();
      final eventsA = <DeviceStatus>[];
      final eventsB = <DeviceStatus>[];
      final subscriptionA = repository.watchStatus('device-a').listen(eventsA.add);
      final subscriptionB = repository.watchStatus('device-b').listen(eventsB.add);
      await Future<void>.delayed(Duration.zero);

      repository.simulateIncomingCall('device-a');
      await Future<void>.delayed(Duration.zero);

      expect(eventsA.last.hasIncomingCall, isTrue);
      expect(eventsB, hasLength(1));
      expect(eventsB.single.hasIncomingCall, isFalse);

      await subscriptionA.cancel();
      await subscriptionB.cancel();
    });
  });
}
