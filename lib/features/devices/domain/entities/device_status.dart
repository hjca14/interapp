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

  final bool isOnline;
  final int? batteryLevel;
  final DeviceConnectionType connectionType;
  final String? errorMessage;
  final String? firmwareVersion;
  final DateTime? lastSeen;
  final bool hasIncomingCall;
  final String? wifiName;
}
