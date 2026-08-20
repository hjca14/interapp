import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/biometric_lock.dart';

/// Persists only biometric-lock enablement and timeout, never credentials.
class SharedPreferencesBiometricLockSettingsRepository
    implements BiometricLockSettingsRepository {
  static const _enabledKey = 'biometric_lock_enabled';
  static const _timeoutKey = 'biometric_lock_timeout_seconds';

  @override
  Future<BiometricLockSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return BiometricLockSettings(
      enabled: preferences.getBool(_enabledKey) ?? false,
      backgroundTimeout: Duration(
        seconds: preferences.getInt(_timeoutKey) ?? 60,
      ),
    );
  }

  @override
  Future<void> save(BiometricLockSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, settings.enabled);
    await preferences.setInt(
      _timeoutKey,
      settings.backgroundTimeout.inSeconds,
    );
  }
}
