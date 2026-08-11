import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_device_backend_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';

void main() {
  group('LocalDeviceBackendRepository', () {
    test(
      'reports commands as failed with cloudUnavailable instead of faking success',
      () async {
        final repository = LocalDeviceBackendRepository();

        final openDoorResult = await repository.openDoor('device-1');
        final restartResult = await repository.restart('device-1');

        expect(openDoorResult.status, DeviceCommandStatus.failed);
        expect(openDoorResult.error, DeviceProtocolError.cloudUnavailable);
        expect(restartResult.status, DeviceCommandStatus.failed);
        expect(restartResult.error, DeviceProtocolError.cloudUnavailable);
      },
    );

    test(
      'reports device claiming as unavailable instead of fabricating ownership',
      () async {
        final repository = LocalDeviceBackendRepository();

        final result = await repository.claimDevice(
          const DeviceClaim(deviceId: 'ib-abc123', claimCode: 'secret'),
        );

        expect(result.status, DeviceClaimStatus.backendUnavailable);
        expect(result.deviceId, isNull);
      },
    );

    test(
      'reports no devices and no events instead of inventing data',
      () async {
        final repository = LocalDeviceBackendRepository();

        expect(await repository.getDevices(), isEmpty);
        expect(await repository.getRecentEvents('device-1'), isEmpty);
        expect(
          await repository.watchDeviceEvents('device-1').toList(),
          isEmpty,
        );
      },
    );

    test('reports every device as offline rather than guessing', () async {
      final repository = LocalDeviceBackendRepository();

      final status = await repository.getDeviceStatus('device-1');

      expect(status.isOnline, isFalse);
    });
  });
}
