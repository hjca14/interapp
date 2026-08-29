import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract interface class InstallationIdStore {
  Future<String> getOrCreate();
}

abstract interface class StringPreferenceStore {
  String? getString(String key);
  Future<bool> setString(String key, String value);
}

class InstallationIdStoreFailure implements Exception {
  const InstallationIdStoreFailure();

  @override
  String toString() => 'Não foi possível salvar a identificação da instalação.';
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
  Future<String> getOrCreate() async {
    final existingAttempt = _value;
    if (existingAttempt != null) {
      return existingAttempt;
    }

    final attempt = _loadOrCreate();
    _value = attempt;
    try {
      return await attempt;
    } on Object {
      if (identical(_value, attempt)) {
        _value = null;
      }
      rethrow;
    }
  }

  Future<String> _loadOrCreate() async {
    final stored = _preferences.getString(preferenceKey);
    if (stored != null && _validUuidV4.hasMatch(stored)) return stored;
    final generated = _uuid.v4();
    final persisted = await _preferences.setString(preferenceKey, generated);
    if (!persisted) {
      throw const InstallationIdStoreFailure();
    }
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
