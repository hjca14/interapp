/// A nearby InterBridge found during BLE onboarding scan, before it's
/// claimed by the user.
///
/// Only [friendlyName] belongs in normal user-facing UI — see
/// PROJECT_CONTEXT.md, "setup_code vs device_id": a regular user should
/// never need to read/type the full technical id. [deviceId] exists for the
/// coordinator/backend and for a future diagnostics/developer view only.
class DiscoveredInterBridge {
  const DiscoveredInterBridge({required this.deviceId, required this.friendlyName});

  final String deviceId;
  final String friendlyName;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredInterBridge && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

/// Derives a short, human-friendly name (e.g. `InterBridge-A91C`) from a
/// technical `device_id` (e.g. `ib-7f3a91c2d84e4fa9b621b88658fdca77`), for
/// transports that only advertise the raw id over BLE.
String friendlyInterBridgeName(String deviceId) {
  final hexOnly = deviceId.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  final suffix = hexOnly.length >= 4 ? hexOnly.substring(hexOnly.length - 4) : hexOnly;
  return 'InterBridge-${suffix.toUpperCase()}';
}
