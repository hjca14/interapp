import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// UI-facing phase of an `OPEN_DOOR` request, per
/// `docs/communication-protocol.md` §19/§20.1.
///
/// [accepted] is a real waiting state a future backend can report before
/// the terminal result arrives; the local/stub repository skips straight to
/// a terminal phase since it has no asynchronous execution to wait on.
enum OpenDoorRequestPhase {
  idle,
  sending,
  accepted,
  completed,
  failed,
  rejected,
  timedOut,
}

class OpenDoorRequestState {
  const OpenDoorRequestState({
    this.phase = OpenDoorRequestPhase.idle,
    this.error,
  });

  final OpenDoorRequestPhase phase;

  /// Set when [phase] is [OpenDoorRequestPhase.failed],
  /// [OpenDoorRequestPhase.rejected] or [OpenDoorRequestPhase.timedOut].
  final DeviceProtocolError? error;

  bool get isBusy =>
      phase == OpenDoorRequestPhase.sending ||
      phase == OpenDoorRequestPhase.accepted;
}

/// Drives the "Abrir porta" button's state machine for one device.
///
/// A [Notifier] (not `AsyncNotifier`) because this models an explicit, small
/// state machine the UI reacts to — not just "loading vs. loaded data".
/// [openDoor] guards against double-tap/concurrent requests via
/// [OpenDoorRequestState.isBusy] and never automatically retries a
/// timed-out/expired command, per §20.1.
class DeviceCommandController extends Notifier<OpenDoorRequestState> {
  DeviceCommandController(this.deviceId);

  final String deviceId;

  @override
  OpenDoorRequestState build() => const OpenDoorRequestState();

  Future<void> openDoor() async {
    if (state.isBusy) return;
    state = const OpenDoorRequestState(phase: OpenDoorRequestPhase.sending);
    final result = await ref
        .read(deviceConnectionRepositoryProvider)
        .openDoor(deviceId);
    state = switch (result.status) {
      DeviceCommandStatus.accepted => const OpenDoorRequestState(
        phase: OpenDoorRequestPhase.accepted,
      ),
      DeviceCommandStatus.completed => const OpenDoorRequestState(
        phase: OpenDoorRequestPhase.completed,
      ),
      DeviceCommandStatus.failed => OpenDoorRequestState(
        phase: OpenDoorRequestPhase.failed,
        error: result.error,
      ),
      DeviceCommandStatus.rejected => OpenDoorRequestState(
        phase: OpenDoorRequestPhase.rejected,
        error: result.error,
      ),
      DeviceCommandStatus.timedOut => OpenDoorRequestState(
        phase: OpenDoorRequestPhase.timedOut,
        error: result.error,
      ),
    };
  }

  /// Returns to [OpenDoorRequestPhase.idle] — e.g. once the UI has shown a
  /// terminal result for a while and the button should be usable again.
  void reset() => state = const OpenDoorRequestState();
}

final deviceCommandControllerProvider =
    NotifierProvider.family<
      DeviceCommandController,
      OpenDoorRequestState,
      String
    >(DeviceCommandController.new);
