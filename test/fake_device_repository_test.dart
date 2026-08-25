import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/data/repositories/fake_device_repository.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

void main() {
  ApiDeviceDetail device({String? displayName}) => ApiDeviceDetail(
    deviceId: 'device-1',
    displayName: displayName,
    hardwareVersion: 'HW-1',
    ownershipStatus: 'claimed',
    provisioningStatus: 'active',
    role: DeviceRole.owner,
  );

  test('listDevices reflects seeded devices', () async {
    final repository = FakeDeviceRepository(
      devices: [device(displayName: 'Minha casa')],
    );

    final page = await repository.listDevices();

    expect(page.items.single.deviceId, 'device-1');
    expect(page.items.single.displayName, 'Minha casa');
  });

  test('getDeviceDetails returns the seeded device', () async {
    final repository = FakeDeviceRepository(devices: [device()]);

    final detail = await repository.getDeviceDetails('device-1');

    expect(detail.deviceId, 'device-1');
    expect(detail.displayName, isNull);
  });

  test('getDeviceDetails throws a typed not-found failure for unknown id', () {
    final repository = FakeDeviceRepository();

    expect(
      () => repository.getDeviceDetails('missing'),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.notFound,
        ),
      ),
    );
  });

  test('updateDeviceName sets a custom name deterministically', () async {
    final repository = FakeDeviceRepository(devices: [device()]);

    final updated = await repository.updateDeviceName('device-1', 'Minha casa');

    expect(updated.displayName, 'Minha casa');
    expect(
      (await repository.getDeviceDetails('device-1')).displayName,
      'Minha casa',
    );
  });

  test('updateDeviceName with null clears a previously set name', () async {
    final repository = FakeDeviceRepository(
      devices: [device(displayName: 'Minha casa')],
    );

    final updated = await repository.updateDeviceName('device-1', null);

    expect(updated.displayName, isNull);
  });

  test('updateDeviceName preserves the other detail fields', () async {
    final repository = FakeDeviceRepository(devices: [device()]);

    final updated = await repository.updateDeviceName('device-1', 'Portaria');

    expect(updated.hardwareVersion, 'HW-1');
    expect(updated.ownershipStatus, 'claimed');
    expect(updated.provisioningStatus, 'active');
    expect(updated.role, DeviceRole.owner);
  });
}
