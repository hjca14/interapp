/// The user's saved identity for one InterBridge device — who it is, not how
/// it's doing right now.
///
/// Deliberately holds only `id`, `name` and `createdAt`. Anything that can
/// change without the user editing it (online/offline, firmware, battery...)
/// belongs in [DeviceStatus] instead, not here.
class InterBridgeDevice {
  const InterBridgeDevice({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// Serializes this device to a single tab-separated string so it can be
  /// stored in a `shared_preferences` string list (see
  /// `LocalDevicesRepository`).
  String toStorage() => '$id\t$name\t${createdAt.toIso8601String()}';

  /// Parses a string produced by [toStorage]. Returns `null` for malformed
  /// entries instead of throwing, so one corrupted row doesn't break loading
  /// the whole devices list.
  static InterBridgeDevice? fromStorage(String value) {
    final values = value.split('\t');
    if (values.length != 3 || values[0].isEmpty || values[1].isEmpty) return null;
    return InterBridgeDevice(
      id: values[0],
      name: values[1],
      createdAt: DateTime.tryParse(values[2]) ?? DateTime.now(),
    );
  }
}
