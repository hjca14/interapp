import 'package:interapp/core/protocol/protocol_constants.dart';

/// A remote command sendable to an InterBridge, per
/// `docs/communication-protocol.md` §18.
///
/// [openDoor] and [restart] are the only commands implemented in protocol
/// v1. [answerCall]/[rejectCall]/[endCall] are listed because the protocol
/// reserves them for future call/audio logic — they exist here so a result
/// referencing one (from a future backend) can still be represented, but no
/// controller/UI in this app is allowed to send them yet.
enum DeviceCommandType {
  openDoor,
  restart,

  /// Reserved for future call/audio logic. Not implemented — never offer
  /// this in the UI.
  answerCall,

  /// Reserved for future call/audio logic. Not implemented — never offer
  /// this in the UI.
  rejectCall,

  /// Reserved for future call/audio logic. Not implemented — never offer
  /// this in the UI.
  endCall,

  /// A command name the app doesn't recognize.
  unknown;

  static const Map<String, DeviceCommandType> _byWireValue = {
    'OPEN_DOOR': openDoor,
    'RESTART': restart,
    'ANSWER_CALL': answerCall,
    'REJECT_CALL': rejectCall,
    'END_CALL': endCall,
  };

  static DeviceCommandType fromWireValue(String? value) =>
      _byWireValue[value] ?? unknown;

  String get wireValue {
    switch (this) {
      case openDoor:
        return 'OPEN_DOOR';
      case restart:
        return 'RESTART';
      case answerCall:
        return 'ANSWER_CALL';
      case rejectCall:
        return 'REJECT_CALL';
      case endCall:
        return 'END_CALL';
      case unknown:
        return 'UNKNOWN';
    }
  }
}

/// Conceptual representation of a command envelope, as the backend builds
/// and publishes it to AWS IoT Core — not something the app constructs and
/// sends itself. The app never talks to AWS IoT Core directly (see
/// `docs/communication-integration.md`); this shape mirrors the protocol's
/// command envelope (§18) purely so a result/history the backend hands back
/// can be parsed and displayed.
///
/// [issuedAt]/[expiresAt] are **backend-authoritative**: the backend stamps
/// them before publishing, and the device evaluates expiry against them.
/// The phone's clock is never a security authority and this class is not
/// how the app requests a command — when the app asks the (future) backend
/// to open the door, it only sends the command intent and a client-generated
/// `command_id` (see [generateCommandId]) for idempotency; the backend fills
/// in the rest.
class DeviceCommand {
  const DeviceCommand({
    required this.commandId,
    required this.command,
    required this.issuedAt,
    required this.expiresAt,
    this.payload,
  });

  final String commandId;
  final DeviceCommandType command;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final Map<String, dynamic>? payload;

  /// Serializes to the wire envelope shape (§14/§18). `issued_at`/
  /// `expires_at` are encoded as Unix epoch seconds, not ISO-8601 — see
  /// [dateTimeToEpochSeconds].
  Map<String, dynamic> toJson() {
    return {
      'protocol_version': kProtocolVersion,
      'command_id': commandId,
      'command': command.wireValue,
      'issued_at': dateTimeToEpochSeconds(issuedAt),
      'expires_at': dateTimeToEpochSeconds(expiresAt),
      if (payload != null) 'payload': payload,
    };
  }

  /// Parses a command envelope as received from the backend. Throws
  /// [UnsupportedProtocolVersionException] when `protocol_version` is
  /// present and unsupported.
  factory DeviceCommand.fromJson(Map<String, dynamic> json) {
    final protocolVersion = (json['protocol_version'] as num?)?.toInt();
    if (protocolVersion != null &&
        !isSupportedProtocolVersion(protocolVersion)) {
      throw UnsupportedProtocolVersionException(protocolVersion);
    }
    return DeviceCommand(
      commandId: json['command_id'] as String,
      command: DeviceCommandType.fromWireValue(json['command'] as String?),
      issuedAt: epochSecondsToDateTime((json['issued_at'] as num).toInt()),
      expiresAt: epochSecondsToDateTime((json['expires_at'] as num).toInt()),
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}
