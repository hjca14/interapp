import 'package:local_auth/local_auth.dart';

import '../../domain/services/biometric_lock.dart';

/// Native `local_auth` adapter for Face ID, Touch ID, and Android biometrics.
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication(),
      _biometricOnly = true,
      _reason = 'Desbloqueie o InterBridge para continuar';

  LocalBiometricAuthenticator.deviceAuthentication([
    LocalAuthentication? authentication,
  ]) : _authentication = authentication ?? LocalAuthentication(),
       _biometricOnly = false,
       _reason = 'Confirme sua identidade para abrir a porta';

  final LocalAuthentication _authentication;
  final bool _biometricOnly;
  final String _reason;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      if (!await _authentication.isDeviceSupported()) {
        return BiometricAvailability.unsupported;
      }
      if (!_biometricOnly) return BiometricAvailability.available;
      final enrolled = await _authentication.getAvailableBiometrics();
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Object {
      return BiometricAvailability.unsupported;
    }
  }

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: _reason,
        biometricOnly: _biometricOnly,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthenticationResult.success
          : BiometricAuthenticationResult.canceled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricAuthenticationResult.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          BiometricAuthenticationResult.unsupported,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled =>
          BiometricAuthenticationResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricAuthenticationResult.temporarilyLocked,
        _ => BiometricAuthenticationResult.failed,
      };
    } on Object {
      return BiometricAuthenticationResult.failed;
    }
  }
}
