import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract interface class InstallationIdStore {
  Future<String> getOrCreate();
}

abstract interface class StringPreferenceStore {
  String? getString(String key);
  Future<bool> setString(String key, String value);
}

class SharedPreferencesInstallationIdStore implements InstallationIdStore {
  SharedPreferencesInstallationIdStore(this._preferences, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const preferenceKey = 'push_installation_id_v1';
  final StringPreferenceStore _preferences;
  final Uuid _uuid;
  Future<String>? _value;

  static final _validUuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  Future<String> getOrCreate() => _value ??= _loadOrCreate();

  Future<String> _loadOrCreate() async {
    final stored = _preferences.getString(preferenceKey);
    if (stored != null && _validUuidV4.hasMatch(stored)) return stored;
    final generated = _uuid.v4();
    await _preferences.setString(preferenceKey, generated);
    return generated;
  }
}

class SharedPreferencesStringStore implements StringPreferenceStore {
  SharedPreferencesStringStore(this.preferences);
  final SharedPreferences preferences;
  @override
  String? getString(String key) => preferences.getString(key);
  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
}
