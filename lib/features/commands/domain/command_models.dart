/// Public lifecycle of an asynchronous device command.
enum CommandState { pending, completed, rejected, expired }

/// A validated InterBridge identifier.
final class DeviceId {
  DeviceId(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    if (!RegExp(r'^ib-[0-9a-f]{32}$').hasMatch(value)) {
      throw const FormatException('Invalid device_id');
    }
    return value;
  }
}

/// A validated backend-generated command identifier.
final class CommandId {
  CommandId(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
      throw const FormatException('Invalid command_id');
    }
    return value;
  }
}

/// A timestamp whose wire representation must explicitly denote UTC.
final class UtcTimestamp {
  UtcTimestamp._(this.value);

  final DateTime value;

  factory UtcTimestamp.parse(String source) {
    if (!source.endsWith('Z')) {
      throw const FormatException('Timestamp is not UTC');
    }
    final parsed = DateTime.tryParse(source);
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('Invalid timestamp');
    }
    return UtcTimestamp._(parsed);
  }
}

/// Exact request supported by Phase 2D. Parameters intentionally stay empty.
final class OpenDoorRequest {
  const OpenDoorRequest();

  Map<String, dynamic> toJson() => const {
    'command': 'OPEN_DOOR',
    'parameters': <String, dynamic>{},
  };
}

final class CommandRejection {
  const CommandRejection(this.code);

  final String code;
}

sealed class DeviceCommandSnapshot {
  const DeviceCommandSnapshot({required this.commandId, required this.state});

  final CommandId commandId;
  final CommandState state;
}

/// A 202/PENDING response only acknowledges queuing. It never means that the
/// device received MQTT, executed the command, or opened a gate.
final class AcceptedCommand extends DeviceCommandSnapshot {
  const AcceptedCommand({
    required super.commandId,
    required this.issuedAt,
    required this.expiresAt,
  }) : super(state: CommandState.pending);

  final UtcTimestamp issuedAt;
  final UtcTimestamp expiresAt;
}

final class CommandStatus extends DeviceCommandSnapshot {
  const CommandStatus({
    required super.commandId,
    required super.state,
    this.rejection,
  });

  final CommandRejection? rejection;

  bool get isTerminal => state != CommandState.pending;
}
