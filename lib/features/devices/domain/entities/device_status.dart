enum DeviceConnectionType { bluetooth, wifi, localNetwork, unknown }

/// Dynamic telemetry received from an InterBridge device.
///
/// This entity is intentionally independent of [InterBridgeDevice], whose data
/// describes the user's saved device identity.
class DeviceStatus {
  const DeviceStatus({
    required this.isOnline,
    this.batteryLevel,
    this.connectionType = DeviceConnectionType.unknown,
    this.errorMessage,
    this.firmwareVersion,
    this.lastSeen,
    this.hasIncomingCall = false,
    this.wifiName,
  });

  /// Whether the device is currently reachable. The local/prototype
  /// implementation always reports `false` — there's no real hardware to be
  /// online yet, and the UI must not invent an "online" state.
  final bool isOnline;

  /// Battery percentage (0-100), or `null` if unknown/not battery-powered.
  final int? batteryLevel;

  /// Which transport is currently carrying the connection. `unknown` until a
  /// real implementation replaces `LocalDeviceConnectionRepository`.
  final DeviceConnectionType connectionType;

  /// Human-readable error surfaced by the device/transport, if any.
  final String? errorMessage;

  final String? firmwareVersion;

  /// Timestamp of the last time the device was heard from.
  final DateTime? lastSeen;

  /// `true` while the interfone is ringing. `IncomingCallListener` watches
  /// this field (via `deviceStatusProvider`) to trigger the local
  /// notification and the full-screen ringing UI — see `IncomingCallPage`.
  final bool hasIncomingCall;

  final String? wifiName;
}
