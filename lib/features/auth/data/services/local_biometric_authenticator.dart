import 'package:local_auth/local_auth.dart';

import '../../domain/services/biometric_lock.dart';

/// Native `local_auth` adapter for Face ID, Touch ID, and Android biometrics.
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _authentication.isDeviceSupported() &&
          await _authentication.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: 'Desbloqueie o InterBridge para continuar',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthenticationResult.success
          : BiometricAuthenticationResult.canceled;
    } on Object {
      return BiometricAuthenticationResult.failed;
    }
  }
}
