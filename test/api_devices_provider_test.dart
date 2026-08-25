import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

ApiDeviceSummary _summary(String id, {String? displayName}) => ApiDeviceSummary(
  deviceId: id,
  displayName: displayName,
  role: DeviceRole.owner,
  status: MembershipStatus.active,
);

class _ListOnlyRepository implements DeviceRepository {
  _ListOnlyRepository({this.pages = const []});

  /// Each call to [listDevices] (without a cursor) consumes the next entry;
  /// an entry that's an [Exception] is thrown instead of returned, so tests
  /// can script "fails then recovers".
  final List<Object> pages;
  int listCalls = 0;

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async {
    final entry = pages[listCalls];
    listCalls++;
    if (entry is Exception) throw entry;
    return entry as ApiDevicePage;
  }

  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) => throw UnimplementedError();
}

ProviderContainer _containerWith(_ListOnlyRepository repository) {
  final container = ProviderContainer(
    overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
  );
  return container;
}

void main() {
  test('starts in a loading state before the first page arrives', () {
    final container = _containerWith(
      _ListOnlyRepository(pages: [const ApiDevicePage(items: [])]),
    );
    addTearDown(container.dispose);

    expect(container.read(apiDevicesProvider).loading, isTrue);
  });

  test('loads multiple devices', () async {
    final container = _containerWith(
      _ListOnlyRepository(
        pages: [
          ApiDevicePage(items: [_summary('device-1'), _summary('device-2')]),
        ],
      ),
    );
    addTearDown(container.dispose);

    await container.read(apiDevicesProvider.notifier).refresh();

    final state = container.read(apiDevicesProvider);
    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.items.map((d) => d.deviceId), ['device-1', 'device-2']);
  });

  test('an empty page is a real empty list, not an error', () async {
    final container = _containerWith(
      _ListOnlyRepository(pages: [const ApiDevicePage(items: [])]),
    );
    addTearDown(container.dispose);

    await container.read(apiDevicesProvider.notifier).refresh();

    final state = container.read(apiDevicesProvider);
    expect(state.error, isNull);
    expect(state.items, isEmpty);
  });

  test('a failed refresh is recoverable and retry succeeds', () async {
    final container = _containerWith(
      _ListOnlyRepository(
        pages: [
          Exception('offline'),
          ApiDevicePage(items: [_summary('device-1')]),
        ],
      ),
    );
    addTearDown(container.dispose);

    await container.read(apiDevicesProvider.notifier).refresh();
    expect(container.read(apiDevicesProvider).error, isNotNull);
    expect(container.read(apiDevicesProvider).items, isEmpty);

    await container.read(apiDevicesProvider.notifier).refresh();
    final state = container.read(apiDevicesProvider);
    expect(state.error, isNull);
    expect(state.items.single.deviceId, 'device-1');
  });

  test('applyRenamedDevice updates only the matching device', () async {
    final container = _containerWith(
      _ListOnlyRepository(
        pages: [
          ApiDevicePage(
            items: [
              _summary('device-1', displayName: 'Portaria'),
              _summary('device-2', displayName: 'Interfone'),
            ],
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    await container.read(apiDevicesProvider.notifier).refresh();

    container
        .read(apiDevicesProvider.notifier)
        .applyRenamedDevice('device-1', 'Minha casa');

    final items = container.read(apiDevicesProvider).items;
    expect(
      items.firstWhere((d) => d.deviceId == 'device-1').displayName,
      'Minha casa',
    );
    expect(
      items.firstWhere((d) => d.deviceId == 'device-2').displayName,
      'Interfone',
    );
  });

  test(
    'applyRenamedDevice is a no-op for a device that is not loaded',
    () async {
      final container = _containerWith(
        _ListOnlyRepository(
          pages: [
            ApiDevicePage(items: [_summary('device-1')]),
          ],
        ),
      );
      addTearDown(container.dispose);
      await container.read(apiDevicesProvider.notifier).refresh();

      container
          .read(apiDevicesProvider.notifier)
          .applyRenamedDevice('unknown-device', 'Nova casa');

      expect(
        container.read(apiDevicesProvider).items.single.deviceId,
        'device-1',
      );
    },
  );
}
