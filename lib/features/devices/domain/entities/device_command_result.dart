import 'package:interapp/features/devices/domain/entities/device_command.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

/// A command's lifecycle status, per `docs/communication-protocol.md` §19
/// and §20.1.
///
/// [accepted], [completed], [failed] and [rejected] are the four statuses
/// the device/backend actually put on the wire. [timedOut] is different: it
/// is synthesized locally (by the backend or, absent a backend, by the app)
/// when no terminal response arrives before the deadline — the protocol is
/// explicit that this does **not** authorize automatically replaying an
/// expired physical command (§20.1).
enum DeviceCommandStatus {
  accepted,
  completed,
  failed,
  rejected,
  timedOut;

  bool get isTerminal => this != accepted;
}

/// The outcome of one [DeviceCommand], as the app should observe it.
///
/// Mirrors the command-response envelope from §19 (`command_id`, `command`,
/// `status`, optional `error`), minus the wire-level `device_id`/
/// `protocol_version` fields the app doesn't need to carry around once
/// parsed.
class DeviceCommandResult {
  const DeviceCommandResult({
    required this.commandId,
    required this.command,
    required this.status,
    this.error,
  });

  final String commandId;
  final DeviceCommandType command;
  final DeviceCommandStatus status;

  /// Only meaningful when [status] is [DeviceCommandStatus.failed] or
  /// [DeviceCommandStatus.rejected].
  final DeviceProtocolError? error;
}
