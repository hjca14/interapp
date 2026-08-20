import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/shared_preferences_biometric_lock_settings_repository.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('biometric lock is disabled by default', () async {
    SharedPreferences.setMockInitialValues({});
    final settings =
        await SharedPreferencesBiometricLockSettingsRepository().load();

    expect(settings.enabled, isFalse);
    expect(settings.backgroundTimeout, const Duration(minutes: 1));
  });

  test('persists only enabled state and background timeout', () async {
    SharedPreferences.setMockInitialValues({});
    final repository =
        SharedPreferencesBiometricLockSettingsRepository();
    await repository.save(
      const BiometricLockSettings(
        enabled: true,
        backgroundTimeout: Duration(minutes: 5),
      ),
    );

    final settings = await repository.load();
    final preferences = await SharedPreferences.getInstance();
    expect(settings.enabled, isTrue);
    expect(settings.backgroundTimeout, const Duration(minutes: 5));
    expect(preferences.getKeys(), {
      'biometric_lock_enabled',
      'biometric_lock_timeout_seconds',
    });
  });
}
