import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/installation_id_store.dart';

class MemoryPreferences implements StringPreferenceStore {
  final values = <String, String>{};
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

void main() {
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('generates, persists and reuses a valid UUID v4 across logout', () async {
    final preferences = MemoryPreferences();
    final store = SharedPreferencesInstallationIdStore(preferences);
    final first = await store.getOrCreate();
    expect(first, matches(uuidV4));
    expect(await store.getOrCreate(), first);
    expect(preferences.values.values.single, first);
  });

  test('replaces a corrupted value', () async {
    final preferences = MemoryPreferences()
      ..values[SharedPreferencesInstallationIdStore.preferenceKey] = 'broken';
    final value = await SharedPreferencesInstallationIdStore(
      preferences,
    ).getOrCreate();
    expect(value, matches(uuidV4));
    expect(value, isNot('broken'));
  });

  test('independent installations get different IDs', () async {
    final first = await SharedPreferencesInstallationIdStore(
      MemoryPreferences(),
    ).getOrCreate();
    final second = await SharedPreferencesInstallationIdStore(
      MemoryPreferences(),
    ).getOrCreate();
    expect(first, isNot(second));
  });
}
