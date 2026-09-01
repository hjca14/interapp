import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../../domain/entities/auth_session.dart' as domain;
import '../../domain/repositories/auth_repository.dart';
import 'auth_diagnostic.dart';

/// Cognito implementation of [AuthRepository] backed by the official SDK.
///
/// The repository is the only auth layer that handles provider tokens. Widgets
/// receive only [domain.AuthSession] and sanitized [AuthFailure] values.
class CognitoAuthRepository implements AuthRepository {
  CognitoAuthRepository({CognitoAuthGateway? authGateway})
    : _authGateway = authGateway ?? const AmplifyCognitoAuthGateway();

  final CognitoAuthGateway _authGateway;
  final _sessionChanges = StreamController<domain.AuthSession>.broadcast();

  @override
  Stream<domain.AuthSession> watchSession() async* {
    yield await currentSession;
    yield* _sessionChanges.stream;
  }

  @override
  Future<domain.AuthSession> get currentSession async {
    try {
      final amplifySession = await Amplify.Auth.fetchAuthSession();
      if (!amplifySession.isSignedIn) {
        return const domain.AuthSession.signedOut();
      }

      final user = await Amplify.Auth.getCurrentUser();
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return domain.AuthSession(
        isSignedIn: true,
        userId: user.userId,
        email: _findEmail(attributes),
      );
    } on AuthException {
      return const domain.AuthSession.signedOut();
    }
  }

  @override
  Future<AuthSignUpResult> signUp(String email, String password) {
    return _runGuarded('sign_up', () async {
      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(
          userAttributes: {CognitoUserAttributeKey.email: email},
        ),
      );
      return AuthSignUpResult(confirmationRequired: !result.isSignUpComplete);
    });
  }

  @override
  Future<void> confirmSignUp(String email, String code) {
    return _runGuarded('confirm_sign_up', () async {
      await Amplify.Auth.confirmSignUp(username: email, confirmationCode: code);
    });
  }

  @override
  Future<void> resendSignUpCode(String email) {
    return _runGuarded('resend_sign_up_code', () async {
      await Amplify.Auth.resendSignUpCode(username: email);
    });
  }

  @override
  Future<void> signIn(String email, String password) {
    return _runGuarded('sign_in', () async {
      final result = await Amplify.Auth.signIn(
        username: email,
        password: password,
      );
      if (!result.isSignedIn) {
        throw const AuthFailure(
          AuthFailureKind.unknown,
          'Não foi possível concluir o login.',
        );
      }
      _sessionChanges.add(await currentSession);
    });
  }

  @override
  Future<void> signOut() {
    return _runGuarded('sign_out', () async {
      await _authGateway.signOut();
      _sessionChanges.add(const domain.AuthSession.signedOut());
    });
  }

  @override
  Future<void> beginPasswordReset(String email) {
    return _runGuarded('begin_password_reset', () async {
      final result = await _authGateway.resetPassword(username: email);
      switch (result.nextStep.updateStep) {
        case AuthResetPasswordStep.confirmResetPasswordWithCode:
          return;
        case AuthResetPasswordStep.done:
          // Not a real failure: the only channel available to tell the UI
          // to skip the code screen without widening this method's return
          // type. Caught separately from provider exceptions below, so it
          // never goes through diagnostic logging or exception mapping.
          throw const AuthFailure(
            AuthFailureKind.passwordResetComplete,
            'A redefinição já foi concluída. Entre com sua nova senha.',
          );
      }
    });
  }

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) {
    return _runGuarded('confirm_password_reset', () async {
      await _authGateway.confirmResetPassword(
        username: email,
        newPassword: newPassword,
        confirmationCode: code,
      );
    });
  }

  @override
  Future<void> changePassword(String currentPassword, String newPassword) {
    return _runGuarded('change_password', () async {
      try {
        await _authGateway.updatePassword(
          oldPassword: currentPassword,
          newPassword: newPassword,
        );
      } on SignedOutException {
        await _invalidateSessionSafely();
        throw const AuthFailure(
          AuthFailureKind.notAuthenticated,
          'Você precisa entrar novamente para continuar.',
        );
      } on NotAuthorizedServiceException {
        // Cognito's ChangePassword API reuses NotAuthorizedException both for
        // a wrong current password and for an expired/invalid access token.
        // These are never disambiguated by exception text/message/language —
        // that wording is not a stable contract. Instead, ask Amplify to
        // actually verify the session with one bounded forced refresh: if it
        // is still valid, the password itself was wrong; if not (or the
        // check itself fails), fail closed as an expired session.
        if (await _hasValidSessionSafely()) {
          throw const AuthFailure(
            AuthFailureKind.incorrectCurrentPassword,
            'Senha atual incorreta.',
          );
        }
        await _invalidateSessionSafely();
        throw const AuthFailure(
          AuthFailureKind.sessionExpired,
          'Sua sessão expirou. Entre novamente.',
        );
      } on PasswordHistoryPolicyViolationException {
        throw const AuthFailure(
          AuthFailureKind.invalidPassword,
          'A nova senha não pode repetir uma senha usada recentemente.',
        );
      }
    });
  }

  /// Fail-closed: any failure while checking the session — including the
  /// forced refresh itself throwing — is treated as "no valid session",
  /// never as "valid". A single bounded attempt; never retried or looped.
  Future<bool> _hasValidSessionSafely() async {
    try {
      return await _authGateway.hasValidSessionAfterForceRefresh();
    } on Object {
      return false;
    }
  }

  /// Invalidates the session and always converges local state to signed-out,
  /// even if the underlying sign-out call itself fails — no raw exception or
  /// provider message from that failure is ever allowed to escape here.
  Future<void> _invalidateSessionSafely() async {
    try {
      await invalidateSession();
    } on Object {
      _sessionChanges.add(const domain.AuthSession.signedOut());
    }
  }

  /// Obtains the Cognito **access token**, never the ID token.
  ///
  /// Amplify owns secure persistence and refresh-token rotation. Callers may
  /// request one forced refresh for the bounded 401 retry in the HTTP client.
  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) {
    return _runGuarded('get_access_token', () async {
      final session =
          await Amplify.Auth.fetchAuthSession(
                options: FetchAuthSessionOptions(forceRefresh: forceRefresh),
              )
              as CognitoAuthSession;
      return session.userPoolTokensResult.value.accessToken.raw;
    });
  }

  @override
  Future<void> invalidateSession() => signOut();

  static String? _findEmail(List<AuthUserAttribute> attributes) {
    for (final attribute in attributes) {
      if (attribute.userAttributeKey == CognitoUserAttributeKey.email) {
        return attribute.value;
      }
    }
    return null;
  }

  /// Runs [action] for [operation] (a stable, code-controlled name from a
  /// closed vocabulary — e.g. `sign_in`, `confirm_password_reset` — never
  /// user input), mapping any [AuthException] contextually: the same
  /// exception type can mean different things depending on which operation
  /// raised it, so mapping is dispatched by [operation] rather than global.
  Future<T> _runGuarded<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on AuthException catch (exception) {
      emitAuthDiagnostic(operation, exception);
      throw _mapAuthException(operation, exception);
    }
  }

  static AuthFailure _mapAuthException(
    String operation,
    AuthException exception,
  ) {
    return switch (operation) {
      'confirm_password_reset' => _mapConfirmPasswordResetException(exception),
      'begin_password_reset' => _mapBeginPasswordResetException(exception),
      _ => _mapCommonAuthException(exception),
    };
  }

  /// Exhaustive, reset-confirmation-specific mapping. A
  /// [NotAuthorizedServiceException] here is deliberately never reused as
  /// the login "e-mail ou senha inválidos" message: no password is being
  /// verified during reset confirmation, and doing so could also confirm or
  /// deny that an account exists.
  static AuthFailure _mapConfirmPasswordResetException(
    AuthException exception,
  ) {
    if (exception is CodeMismatchException ||
        exception is ExpiredCodeException) {
      return const AuthFailure(
        AuthFailureKind.invalidOrExpiredCode,
        'Código inválido ou expirado. Solicite um novo código.',
      );
    }
    if (exception is InvalidPasswordException) {
      return const AuthFailure(
        AuthFailureKind.invalidPassword,
        'A senha não atende à política informada.',
      );
    }
    if (exception is PasswordHistoryPolicyViolationException) {
      return const AuthFailure(
        AuthFailureKind.invalidPassword,
        'Escolha uma senha que você ainda não tenha usado.',
      );
    }
    if (exception is LimitExceededException ||
        exception is TooManyRequestsException) {
      return const AuthFailure(
        AuthFailureKind.rateLimited,
        'Muitas tentativas. Aguarde e tente novamente.',
      );
    }
    if (exception is NetworkException) {
      return const AuthFailure(
        AuthFailureKind.unavailable,
        'Sem conexão. Verifique sua internet e tente novamente.',
      );
    }
    // NotAuthorizedServiceException, UserNotFoundException,
    // InvalidParameterException, and anything else land here: none can be
    // detailed further without risking account-enumeration or reusing an
    // unrelated context's message.
    return const AuthFailure(
      AuthFailureKind.invalidResetState,
      'Não foi possível redefinir a senha. Solicite um novo código e tente '
      'novamente.',
    );
  }

  /// Never reveals whether the requested account exists.
  static AuthFailure _mapBeginPasswordResetException(AuthException exception) {
    if (exception is LimitExceededException ||
        exception is TooManyRequestsException) {
      return const AuthFailure(
        AuthFailureKind.rateLimited,
        'Muitas tentativas. Aguarde e tente novamente.',
      );
    }
    if (exception is NetworkException) {
      return const AuthFailure(
        AuthFailureKind.unavailable,
        'Sem conexão. Verifique sua internet e tente novamente.',
      );
    }
    return const AuthFailure(
      AuthFailureKind.invalidResetState,
      'Não foi possível iniciar a redefinição de senha. Tente novamente.',
    );
  }

  /// Maps provider exceptions without leaking claims or service messages.
  static AuthFailure _mapCommonAuthException(AuthException exception) {
    if (exception is InvalidPasswordException) {
      return const AuthFailure(
        AuthFailureKind.invalidPassword,
        'A senha não atende à política informada.',
      );
    }
    if (exception is UsernameExistsException) {
      return const AuthFailure(
        AuthFailureKind.userAlreadyExists,
        'Não foi possível concluir o cadastro com esses dados.',
      );
    }
    if (exception is UserNotConfirmedException) {
      return const AuthFailure(
        AuthFailureKind.userNotConfirmed,
        'Confirme seu e-mail para continuar.',
      );
    }
    if (exception is CodeMismatchException ||
        exception is ExpiredCodeException) {
      return const AuthFailure(
        AuthFailureKind.invalidOrExpiredCode,
        'Código inválido ou expirado.',
      );
    }
    if (exception is LimitExceededException ||
        exception is TooManyRequestsException) {
      return const AuthFailure(
        AuthFailureKind.rateLimited,
        'Muitas tentativas. Aguarde e tente novamente.',
      );
    }
    if (exception is NotAuthorizedServiceException ||
        exception is UserNotFoundException) {
      return const AuthFailure(
        AuthFailureKind.invalidCredentials,
        'E-mail ou senha inválidos.',
      );
    }
    if (exception is NetworkException) {
      return const AuthFailure(
        AuthFailureKind.unavailable,
        'Sem conexão. Verifique sua internet e tente novamente.',
      );
    }
    return const AuthFailure(
      AuthFailureKind.unknown,
      'Não foi possível concluir a operação. Tente novamente.',
    );
  }
}

/// Narrow seam over the global `Amplify.Auth` facade covering only the calls
/// [CognitoAuthRepository] needs to fake in tests without a configured
/// Amplify plugin. Every other operation still calls `Amplify.Auth` directly.
abstract class CognitoAuthGateway {
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> signOut();

  /// Whether the current user still has a valid, authenticated session after
  /// one forced token refresh. Used only to tell a wrong current password
  /// apart from an expired/invalid session when `updatePassword` throws the
  /// same exception type for both — never by reading exception text.
  ///
  /// Returns a plain [bool]; the access token itself is never exposed here.
  Future<bool> hasValidSessionAfterForceRefresh();

  /// Starts password recovery for [username], returning the SDK's own
  /// next-step contract rather than assuming a code confirmation follows.
  Future<ResetPasswordResult> resetPassword({required String username});

  Future<void> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  });
}

/// Production [CognitoAuthGateway] delegating to the real Amplify Auth
/// category.
class AmplifyCognitoAuthGateway implements CognitoAuthGateway {
  const AmplifyCognitoAuthGateway();

  @override
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) => Amplify.Auth.updatePassword(
    oldPassword: oldPassword,
    newPassword: newPassword,
  );

  @override
  Future<void> signOut() => Amplify.Auth.signOut();

  @override
  Future<bool> hasValidSessionAfterForceRefresh() async {
    final session = await Amplify.Auth.fetchAuthSession(
      options: FetchAuthSessionOptions(forceRefresh: true),
    );
    return session.isSignedIn;
  }

  @override
  Future<ResetPasswordResult> resetPassword({required String username}) =>
      Amplify.Auth.resetPassword(username: username);

  @override
  Future<void> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) => Amplify.Auth.confirmResetPassword(
    username: username,
    newPassword: newPassword,
    confirmationCode: confirmationCode,
  );
}
