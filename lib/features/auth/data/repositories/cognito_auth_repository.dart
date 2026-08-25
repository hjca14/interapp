import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../../domain/entities/auth_session.dart' as domain;
import '../../domain/repositories/auth_repository.dart';

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
    return _runGuarded(() async {
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
    return _runGuarded(() async {
      await Amplify.Auth.confirmSignUp(username: email, confirmationCode: code);
    });
  }

  @override
  Future<void> resendSignUpCode(String email) {
    return _runGuarded(() async {
      await Amplify.Auth.resendSignUpCode(username: email);
    });
  }

  @override
  Future<void> signIn(String email, String password) {
    return _runGuarded(() async {
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
    return _runGuarded(() async {
      await _authGateway.signOut();
      _sessionChanges.add(const domain.AuthSession.signedOut());
    });
  }

  @override
  Future<void> beginPasswordReset(String email) {
    return _runGuarded(() async {
      await Amplify.Auth.resetPassword(username: email);
    });
  }

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) {
    return _runGuarded(() async {
      await Amplify.Auth.confirmResetPassword(
        username: email,
        newPassword: newPassword,
        confirmationCode: code,
      );
    });
  }

  @override
  Future<void> changePassword(String currentPassword, String newPassword) {
    return _runGuarded(() async {
      try {
        await _authGateway.updatePassword(
          oldPassword: currentPassword,
          newPassword: newPassword,
        );
      } on SignedOutException {
        await invalidateSession();
        throw const AuthFailure(
          AuthFailureKind.notAuthenticated,
          'Você precisa entrar novamente para continuar.',
        );
      } on NotAuthorizedServiceException catch (exception) {
        if (_looksLikeWrongCurrentPassword(exception.message)) {
          throw const AuthFailure(
            AuthFailureKind.incorrectCurrentPassword,
            'Senha atual incorreta.',
          );
        }
        // Cognito's ChangePassword API reuses NotAuthorizedException both for
        // a wrong current password and for an expired/invalid access token;
        // this message is never shown to the user, only used to route to the
        // right sanitized failure.
        await invalidateSession();
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

  static bool _looksLikeWrongCurrentPassword(String message) =>
      message.toLowerCase().contains('incorrect');

  /// Obtains the Cognito **access token**, never the ID token.
  ///
  /// Amplify owns secure persistence and refresh-token rotation. Callers may
  /// request one forced refresh for the bounded 401 retry in the HTTP client.
  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) {
    return _runGuarded(() async {
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

  Future<T> _runGuarded<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthFailure {
      rethrow;
    } on AuthException catch (exception) {
      throw _mapAuthException(exception);
    }
  }

  /// Maps provider exceptions without leaking claims or service messages.
  static AuthFailure _mapAuthException(AuthException exception) {
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
}
