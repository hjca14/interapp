import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/cloud_device_connection_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_backend_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

void main() {
  group('CloudDeviceConnectionRepository', () {
    test('openDoor delegates straight to the backend repository', () async {
      final repository = CloudDeviceConnectionRepository(
        LocalDeviceBackendRepository(),
      );

      final result = await repository.openDoor('device-1');

      // LocalDeviceBackendRepository has no real backend configured, so the
      // delegated call must surface that honestly, not fabricate success.
      expect(result.status, DeviceCommandStatus.failed);
      expect(result.error, DeviceProtocolError.cloudUnavailable);
    });

    test('watchStatus forwards the backend repository\'s stream', () async {
      final repository = CloudDeviceConnectionRepository(
        LocalDeviceBackendRepository(),
      );

      final status = await repository.watchStatus('device-1').first;

      expect(status.isOnline, isFalse);
    });
  });
}
