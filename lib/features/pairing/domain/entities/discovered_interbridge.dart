/// A nearby InterBridge found during BLE onboarding scan, before it's
/// claimed by the user.
///
/// [transportId] is an opaque, short-lived handle issued by the radio adapter.
/// It is stable only for the current discovery/connection attempt and must not
/// be treated as the permanent product `device_id`. The advertised name is
/// likewise only a discovery/deduplication hint.
class DiscoveredInterBridge {
  const DiscoveredInterBridge({
    String? transportId,
    @Deprecated('Use transportId; this is not a permanent product identity.')
    String? deviceId,
    required this.friendlyName,
  }) : transportId = transportId ?? deviceId!;

  final String transportId;

  @Deprecated('Use transportId; this is not a permanent product identity.')
  String get deviceId => transportId;
  final String friendlyName;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredInterBridge && other.transportId == transportId;

  @override
  int get hashCode => transportId.hashCode;
}

/// Derives a short, human-friendly name (e.g. `InterBridge-A91C`) from a
/// technical `device_id` (e.g. `ib-7f3a91c2d84e4fa9b621b88658fdca77`), for
/// transports that only advertise the raw id over BLE.
String friendlyInterBridgeName(String deviceId) {
  final hexOnly = deviceId.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  final suffix = hexOnly.length >= 4
      ? hexOnly.substring(hexOnly.length - 4)
      : hexOnly;
  return 'InterBridge-${suffix.toUpperCase()}';
}
