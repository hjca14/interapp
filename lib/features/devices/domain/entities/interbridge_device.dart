class InterBridgeDevice {
  const InterBridgeDevice({
    required this.id,
    required this.name,
    this.firmware,
  });

  final String id;
  final String name;
  final String? firmware;

  String toStorage() => '$id\t$name\t${firmware ?? ''}';

  static InterBridgeDevice? fromStorage(String value) {
    final values = value.split('\t');
    if (values.length != 3 || values[0].isEmpty || values[1].isEmpty) return null;
    return InterBridgeDevice(
      id: values[0],
      name: values[1],
      firmware: values[2].isEmpty ? null : values[2],
    );
  }
}
