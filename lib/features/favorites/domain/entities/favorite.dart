class Favorite {
  const Favorite({required this.name, required this.number});
  final String name;
  final String number;

  String toStorage() => '$name\t$number';

  static Favorite? fromStorage(String value) {
    final parts = value.split('\t');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return Favorite(name: parts[0], number: parts[1]);
  }
}
