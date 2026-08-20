import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/shared_preferences_biometric_lock_settings_repository.dart';
import '../../data/services/local_biometric_authenticator.dart';
import '../../domain/services/biometric_lock.dart';
import 'auth_providers.dart';

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (_) => LocalBiometricAuthenticator(),
);

final biometricLockSettingsRepositoryProvider =
    Provider<BiometricLockSettingsRepository>(
      (_) => SharedPreferencesBiometricLockSettingsRepository(),
    );

class BiometricLockSettingsController
    extends AsyncNotifier<BiometricLockSettings> {
  @override
  Future<BiometricLockSettings> build() {
    return ref.watch(biometricLockSettingsRepositoryProvider).load();
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state.value ?? const BiometricLockSettings();
    if (enabled &&
        !await ref.read(biometricAuthenticatorProvider).isAvailable()) {
      throw const BiometricUnavailableException();
    }
    final updated = previous.copyWith(enabled: enabled);
    await ref.read(biometricLockSettingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> setTimeout(Duration timeout) async {
    final previous = state.value ?? const BiometricLockSettings();
    final updated = previous.copyWith(backgroundTimeout: timeout);
    await ref.read(biometricLockSettingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }
}

class BiometricUnavailableException implements Exception {
  const BiometricUnavailableException();
}

final biometricLockSettingsProvider =
    AsyncNotifierProvider<
      BiometricLockSettingsController,
      BiometricLockSettings
    >(BiometricLockSettingsController.new);

final biometricUnlockServiceProvider = Provider<BiometricUnlockService>(
  (ref) => BiometricUnlockService(
    ref.watch(authRepositoryProvider),
    ref.watch(biometricAuthenticatorProvider),
  ),
);
