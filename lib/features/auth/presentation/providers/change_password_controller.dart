import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

enum ChangePasswordStatus { initial, submitting, success, failure }

/// State for [ChangePasswordController]. Field errors are local/validation
/// failures; [errorMessage] is the sanitized remote failure, if any. Neither
/// this state nor the controller ever retains the password values themselves
/// — callers pass them into [ChangePasswordController.submit] each time.
class ChangePasswordState {
  const ChangePasswordState({
    this.status = ChangePasswordStatus.initial,
    this.currentPasswordError,
    this.newPasswordError,
    this.confirmPasswordError,
    this.errorMessage,
  });

  final ChangePasswordStatus status;
  final String? currentPasswordError;
  final String? newPasswordError;
  final String? confirmPasswordError;
  final String? errorMessage;

  bool get isSubmitting => status == ChangePasswordStatus.submitting;
  bool get isSuccess => status == ChangePasswordStatus.success;
}

/// Drives the "change password" form: local validation, a single in-flight
/// submission, and mapping the sanitized [AuthFailure] from the auth
/// repository into field or general errors.
///
/// Local validation stays limited to what this form can actually know before
/// asking Cognito: required fields and a matching confirmation. It never
/// rejects an equal current/new password up front, since the typed "current
/// password" cannot be assumed correct without Cognito checking it first —
/// and Cognito DEV has been observed to accept, not reject, that case. Once
/// [AuthRepository.changePassword] returns successfully, the current
/// password is known to have been correct; only then is an equal new
/// password reported as a local "no effective change" field error instead of
/// a success.
class ChangePasswordController extends Notifier<ChangePasswordState> {
  @override
  ChangePasswordState build() => const ChangePasswordState();

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (state.isSubmitting) {
      return;
    }

    final validationFailure = _validate(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    if (validationFailure != null) {
      state = validationFailure;
      return;
    }

    state = const ChangePasswordState(status: ChangePasswordStatus.submitting);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(currentPassword, newPassword);
      if (newPassword == currentPassword) {
        // Cognito DEV was observed accepting updatePassword when the new
        // password equals the current one — it is not rejected server-side.
        // A successful call therefore also confirms currentPassword was
        // correct, so only now is it safe to treat equality as "no
        // effective change" and ask for a genuinely different password,
        // instead of reporting a success that changed nothing.
        state = const ChangePasswordState(
          status: ChangePasswordStatus.failure,
          newPasswordError: 'A nova senha deve ser diferente da atual.',
        );
        return;
      }
      state = const ChangePasswordState(status: ChangePasswordStatus.success);
    } on AuthFailure catch (failure) {
      state = ChangePasswordState(
        status: ChangePasswordStatus.failure,
        errorMessage: failure.safeMessage,
      );
    }
  }

  ChangePasswordState? _validate({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    final currentError = currentPassword.isEmpty
        ? 'Informe sua senha atual.'
        : null;
    final newError = newPassword.isEmpty ? 'Informe a nova senha.' : null;
    String? confirmError;
    if (confirmPassword.isEmpty) {
      confirmError = 'Confirme a nova senha.';
    } else if (newPassword.isNotEmpty && confirmPassword != newPassword) {
      confirmError = 'A confirmação não corresponde à nova senha.';
    }

    if (currentError != null || newError != null || confirmError != null) {
      return ChangePasswordState(
        status: ChangePasswordStatus.failure,
        currentPasswordError: currentError,
        newPasswordError: newError,
        confirmPasswordError: confirmError,
      );
    }

    // A new password identical to the current one is NOT rejected here: this
    // form has no reliable way to know the typed "current password" is
    // actually correct (it could be a typo), so only Cognito can validate
    // both together in the same call. Whatever Cognito decides is mapped by
    // AuthRepository.changePassword into the existing sanitized failures.
    return null;
  }
}

final changePasswordControllerProvider =
    NotifierProvider.autoDispose<ChangePasswordController, ChangePasswordState>(
      ChangePasswordController.new,
    );
