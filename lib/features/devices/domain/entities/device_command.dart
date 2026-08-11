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

/// Conceptual representation of a command the app asked the backend to
/// issue — not something the app builds and publishes to MQTT itself. The
/// app never talks to AWS IoT Core directly (see
/// `docs/communication-integration.md`); this shape mirrors the protocol's
/// command envelope (§18) purely so results/history can reference it.
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
}
