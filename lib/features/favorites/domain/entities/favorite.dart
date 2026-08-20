/// A saved dialer shortcut (a name + a number/extension), scoped to one
/// device — see `LocalFavoritesRepository`, which stores each device's
/// favorites under its own `favorites_<deviceId>` key.
class Favorite {
  const Favorite({required this.name, required this.number});
  final String name;
  final String number;

  /// Serializes to a tab-separated string for `shared_preferences` storage.
  String toStorage() => '$name\t$number';

  /// Parses a string produced by [toStorage]; `null` for malformed entries
  /// so one bad row doesn't break the whole favorites list.
  static Favorite? fromStorage(String value) {
    final parts = value.split('\t');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return null;
    }
    return Favorite(name: parts[0], number: parts[1]);
  }
}
