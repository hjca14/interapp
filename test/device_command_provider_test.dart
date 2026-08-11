import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_command.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';
import 'package:interapp/features/devices/presentation/providers/device_command_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

class _FakeDeviceConnectionRepository implements DeviceConnectionRepository {
  int openDoorCallCount = 0;
  DeviceCommandResult Function() openDoorResult = () =>
      const DeviceCommandResult(
        commandId: 'cmd-test',
        command: DeviceCommandType.openDoor,
        status: DeviceCommandStatus.completed,
      );

  /// When set, [openDoor] waits for this to complete before returning, so
  /// tests can hold a request "in flight".
  Completer<void>? gate;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> dial(String deviceId, String number) async {}

  @override
  Future<DeviceCommandResult> openDoor(String deviceId) async {
    openDoorCallCount++;
    if (gate != null) await gate!.future;
    return openDoorResult();
  }

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) => const Stream.empty();
}

void main() {
  group('DeviceCommandController (open-door state machine)', () {
    test('idle -> sending -> completed on a successful command', () async {
      final fake = _FakeDeviceConnectionRepository();
      final container = ProviderContainer(
        overrides: [deviceConnectionRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(deviceCommandControllerProvider('device-1')).phase,
        OpenDoorRequestPhase.idle,
      );

      final pending = container
          .read(deviceCommandControllerProvider('device-1').notifier)
          .openDoor();
      // Dart runs the notifier method synchronously up to its first `await`,
      // so the "sending" state is already visible here.
      expect(
        container.read(deviceCommandControllerProvider('device-1')).phase,
        OpenDoorRequestPhase.sending,
      );

      await pending;

      expect(
        container.read(deviceCommandControllerProvider('device-1')).phase,
        OpenDoorRequestPhase.completed,
      );
      expect(fake.openDoorCallCount, 1);
    });

    test('a failed/rejected result surfaces the protocol error', () async {
      final fake = _FakeDeviceConnectionRepository()
        ..openDoorResult = () => const DeviceCommandResult(
          commandId: 'cmd-test',
          command: DeviceCommandType.openDoor,
          status: DeviceCommandStatus.rejected,
          error: DeviceProtocolError.notProvisioned,
        );
      final container = ProviderContainer(
        overrides: [deviceConnectionRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container
          .read(deviceCommandControllerProvider('device-1').notifier)
          .openDoor();

      final state = container.read(deviceCommandControllerProvider('device-1'));
      expect(state.phase, OpenDoorRequestPhase.rejected);
      expect(state.error, DeviceProtocolError.notProvisioned);
    });

    test(
      'a second tap while a request is in flight does not send a second command',
      () async {
        final fake = _FakeDeviceConnectionRepository()
          ..gate = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            deviceConnectionRepositoryProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          deviceCommandControllerProvider('device-1').notifier,
        );

        final first = notifier.openDoor();
        final second = notifier.openDoor();

        fake.gate!.complete();
        await first;
        await second;

        expect(fake.openDoorCallCount, 1);
      },
    );

    test('a timed-out result is not automatically retried', () async {
      final fake = _FakeDeviceConnectionRepository()
        ..openDoorResult = () => const DeviceCommandResult(
          commandId: 'cmd-test',
          command: DeviceCommandType.openDoor,
          status: DeviceCommandStatus.timedOut,
        );
      final container = ProviderContainer(
        overrides: [deviceConnectionRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container
          .read(deviceCommandControllerProvider('device-1').notifier)
          .openDoor();

      expect(
        container.read(deviceCommandControllerProvider('device-1')).phase,
        OpenDoorRequestPhase.timedOut,
      );
      expect(fake.openDoorCallCount, 1);
    });

    test('reset() returns to idle', () async {
      final fake = _FakeDeviceConnectionRepository();
      final container = ProviderContainer(
        overrides: [deviceConnectionRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        deviceCommandControllerProvider('device-1').notifier,
      );

      await notifier.openDoor();
      notifier.reset();

      expect(
        container.read(deviceCommandControllerProvider('device-1')).phase,
        OpenDoorRequestPhase.idle,
      );
    });
  });
}
