import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/presentation/pages/incoming_call_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/devices/presentation/widgets/door_command_card.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

class _Devices implements DeviceRepository {
  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async =>
      ApiDeviceDetail(
        deviceId: deviceId,
        displayName: 'Portaria',
        ownershipStatus: 'claimed',
        provisioningStatus: 'active',
        role: DeviceRole.owner,
      );

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async =>
      const ApiDevicePage(items: []);

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) => getDeviceDetails(deviceId);
}

class _Settings implements DeviceSettingsRepository {
  const _Settings(this.value);
  final DeviceSettings value;

  @override
  Future<DeviceSettings> get(String deviceId) async => value;

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {}
}

void main() {
  final intent = RingCallIntent(
    eventId: 'evt-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    deviceId: 'ib-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    occurredAt: DateTime.utc(2026, 8, 31),
  );

  Widget subject(DeviceSettings settings) => ProviderScope(
    overrides: [
      deviceRepositoryProvider.overrideWithValue(_Devices()),
      deviceSettingsRepositoryProvider.overrideWithValue(_Settings(settings)),
    ],
    child: MaterialApp(
      home: IncomingCallPage(intent: intent, onDismiss: () {}),
    ),
  );

  testWidgets(
    'hides door action when local opt-in is disabled',
    (tester) async {
      await tester.pumpWidget(subject(const DeviceSettings()));
      await tester.pumpAndSettle();

      expect(find.byType(DoorCommandCard), findsNothing);
      expect(find.text('Abrir portão'), findsNothing);
    },
  );
}
