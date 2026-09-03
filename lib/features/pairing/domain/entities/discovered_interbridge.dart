/// A nearby InterBridge found during BLE onboarding scan, before it's
/// claimed by the user.
///
/// [transportId] is an opaque, short-lived handle issued by the radio adapter.
/// It is stable only for the current discovery/connection attempt and must not
/// be treated as the permanent product `device_id`. The advertised name is
/// likewise only a discovery/deduplication hint.
class DiscoveredInterBridge {
  const DiscoveredInterBridge({
    required this.transportId,
    required this.friendlyName,
  });

  final String transportId;

  final String friendlyName;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredInterBridge && other.transportId == transportId;

  @override
  int get hashCode => transportId.hashCode;
}
