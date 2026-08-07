import 'package:shared_preferences/shared_preferences.dart';

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
