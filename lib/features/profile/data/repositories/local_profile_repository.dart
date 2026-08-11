import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's own display name locally. There's no auth/backend
/// yet, so "profile" today is just this one string.
class LocalProfileRepository {
  static const _profileNameKey = 'profile_name';

  Future<String?> getName() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_profileNameKey);
  }

  Future<void> saveName(String name) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_profileNameKey, name);
  }
}
