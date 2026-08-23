import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/device_status_presentation.dart';

void main() {
  const id = 'ib-device';
  final health = ApiDeviceHealth(
    intercomState: IntercomState.idle,
    firmwareVersion: '2.0.1',
    lastSeenAt: DateTime.utc(2026, 8, 23, 12),
  );

  test('fresh and recently seen is Online', () {
    final value = ApiDeviceStatus(
      deviceId: id,
      connectivity: DeviceConnectivity.recentlySeen,
      freshness: DeviceFreshness.fresh,
      health: health,
    );
    expect(DeviceStatusPresentation.from(value).label, 'Online');
  });

  test('stale is Offline', () {
    final value = ApiDeviceStatus(
      deviceId: id,
      connectivity: DeviceConnectivity.stale,
      freshness: DeviceFreshness.stale,
      health: health,
    );
    expect(DeviceStatusPresentation.from(value).label, 'Offline');
  });

  test('unknown or missing health is unavailable', () {
    final unknown = ApiDeviceStatus(
      deviceId: id,
      connectivity: DeviceConnectivity.unknown,
      freshness: DeviceFreshness.unknown,
      health: health,
    );
    final missingHealth = ApiDeviceStatus(
      deviceId: id,
      connectivity: DeviceConnectivity.recentlySeen,
      freshness: DeviceFreshness.fresh,
    );
    expect(DeviceStatusPresentation.from(unknown).label, 'Status indisponível');
    expect(
      DeviceStatusPresentation.from(missingHealth).label,
      'Status indisponível',
    );
  });

  test('formats relative and old local timestamps without milliseconds', () {
    final now = DateTime(2026, 8, 23, 12, 30);
    expect(formatLastCommunication(now, now), 'Agora');
    expect(
      formatLastCommunication(now.subtract(const Duration(minutes: 1)), now),
      'Há 1 minuto',
    );
    expect(
      formatLastCommunication(now.subtract(const Duration(minutes: 12)), now),
      'Há 12 minutos',
    );
    final old = formatLastCommunication(
      DateTime(2026, 8, 22, 10, 9, 0, 123),
      now,
    );
    expect(old, '22/08/2026 às 10:09');
    expect(old, isNot(contains('.000')));
  });
}
