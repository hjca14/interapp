import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/shared_preferences_biometric_lock_settings_repository.dart';
import '../../data/services/local_biometric_authenticator.dart';
import '../../domain/services/biometric_lock.dart';
import 'auth_providers.dart';

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (_) => LocalBiometricAuthenticator(),
);

/// Local-auth policy for a sensitive device action. The global session lock
/// remains biometric-only; this instance may also use a secure device
/// credential supported by the platform.
final doorDeviceAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (_) => LocalBiometricAuthenticator.deviceAuthentication(),
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
    if (enabled) {
      final authenticator = ref.read(biometricAuthenticatorProvider);
      final availability = await authenticator.availability();
      if (availability != BiometricAvailability.available) {
        throw BiometricActivationException(
          availability == BiometricAvailability.notEnrolled
              ? BiometricAuthenticationResult.notEnrolled
              : BiometricAuthenticationResult.unsupported,
        );
      }
      final result = await authenticator.authenticate();
      if (result != BiometricAuthenticationResult.success) {
        throw BiometricActivationException(result);
      }
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

class BiometricActivationException implements Exception {
  const BiometricActivationException(this.result);

  final BiometricAuthenticationResult result;
}

String biometricResultMessage(BiometricAuthenticationResult result) =>
    switch (result) {
      BiometricAuthenticationResult.notEnrolled =>
        'Cadastre uma biometria nas configurações do aparelho para continuar.',
      BiometricAuthenticationResult.unsupported =>
        'Este aparelho não oferece suporte à autenticação biométrica.',
      BiometricAuthenticationResult.canceled => 'Autenticação cancelada.',
      BiometricAuthenticationResult.temporarilyLocked =>
        'Biometria temporariamente bloqueada. Aguarde e tente novamente.',
      BiometricAuthenticationResult.failed =>
        'Não foi possível confirmar sua biometria. Tente novamente.',
      BiometricAuthenticationResult.success => '',
    };

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
