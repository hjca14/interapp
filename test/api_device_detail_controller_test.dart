import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/fake_device_repository.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

class _FailingUpdateRepository implements DeviceRepository {
  _FailingUpdateRepository(this._detail);
  final ApiDeviceDetail _detail;

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async =>
      const ApiDevicePage(items: []);

  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async => _detail;

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) {
    throw Exception('backend rejected the rename');
  }
}

void main() {
  const deviceId = 'device-1';
  ApiDeviceDetail baseDevice({String? displayName}) => ApiDeviceDetail(
    deviceId: deviceId,
    displayName: displayName,
    hardwareVersion: 'HW-1',
    ownershipStatus: 'claimed',
    provisioningStatus: 'active',
    role: DeviceRole.owner,
  );

  test('updateName confirms the rename and reflects it in state', () async {
    final container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(
          FakeDeviceRepository(devices: [baseDevice()]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Realistically the list is already loaded (HomePage) before the user
    // reaches the rename screen — settle it here too, so `updateName`'s
    // `apiDevicesProvider.notifier` read doesn't leave a first-build
    // microtask racing against `container.dispose()` at teardown.
    await container.read(apiDevicesProvider.notifier).refresh();
    await container.read(apiDeviceDetailProvider(deviceId).future);
    await container
        .read(apiDeviceDetailProvider(deviceId).notifier)
        .updateName('Minha casa');

    expect(
      container.read(apiDeviceDetailProvider(deviceId)).value?.displayName,
      'Minha casa',
    );
  });

  test('updateName(null) clears a previously set custom name', () async {
    final container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(
          FakeDeviceRepository(devices: [baseDevice(displayName: 'Portaria')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(apiDevicesProvider.notifier).refresh();
    await container.read(apiDeviceDetailProvider(deviceId).future);
    await container
        .read(apiDeviceDetailProvider(deviceId).notifier)
        .updateName(null);

    expect(
      container.read(apiDeviceDetailProvider(deviceId)).value?.displayName,
      isNull,
    );
  });

  test('a successful rename is reflected in the device list too', () async {
    final repository = FakeDeviceRepository(
      devices: [baseDevice(displayName: 'Portaria')],
    );
    final container = ProviderContainer(
      overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(apiDevicesProvider.notifier).refresh();
    await container.read(apiDeviceDetailProvider(deviceId).future);
    await container
        .read(apiDeviceDetailProvider(deviceId).notifier)
        .updateName('Minha casa');

    final listed = container
        .read(apiDevicesProvider)
        .items
        .firstWhere((d) => d.deviceId == deviceId);
    expect(listed.displayName, 'Minha casa');
  });

  test('a failed rename leaves the previous detail state untouched', () async {
    final container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(
          _FailingUpdateRepository(baseDevice(displayName: 'Portaria')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(apiDeviceDetailProvider(deviceId).future);

    await expectLater(
      container
          .read(apiDeviceDetailProvider(deviceId).notifier)
          .updateName('Nome novo'),
      throwsException,
    );

    expect(
      container.read(apiDeviceDetailProvider(deviceId)).value?.displayName,
      'Portaria',
    );
  });
}
