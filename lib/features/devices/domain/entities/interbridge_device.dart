class InterBridgeDevice {
  const InterBridgeDevice({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  String toStorage() => '$id\t$name\t${createdAt.toIso8601String()}';

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
