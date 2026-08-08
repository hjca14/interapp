import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalDevicesRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getAll() returns an empty list when nothing was saved', () async {
      final repository = LocalDevicesRepository();

      expect(await repository.getAll(), isEmpty);
    });

    test('saveAll() then getAll() round-trips the devices', () async {
      final repository = LocalDevicesRepository();
      final devices = [
        InterBridgeDevice(id: '1', name: 'Casa', createdAt: DateTime.utc(2026, 1, 1)),
        InterBridgeDevice(id: '2', name: 'Trabalho', createdAt: DateTime.utc(2026, 2, 1)),
      ];

      await repository.saveAll(devices);
      final reloaded = await repository.getAll();

      expect(reloaded.map((device) => device.id), ['1', '2']);
      expect(reloaded.map((device) => device.name), ['Casa', 'Trabalho']);
    });

    test('malformed stored entries are skipped instead of crashing getAll()', () async {
      SharedPreferences.setMockInitialValues({
        'interbridge_devices': ['1\tCasa\t2026-01-01T00:00:00.000Z', 'garbage', ''],
      });
      final repository = LocalDevicesRepository();

      final devices = await repository.getAll();

      expect(devices, hasLength(1));
      expect(devices.single.id, '1');
    });

    test('selected device id round-trips', () async {
      final repository = LocalDevicesRepository();

      expect(await repository.getSelectedId(), isNull);

      await repository.setSelectedId('device-1');

      expect(await repository.getSelectedId(), 'device-1');
    });
  });
}
