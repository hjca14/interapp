import '../entities/auth_session.dart';

/// Provider-independent contract for human authentication.
abstract class AuthRepository {
  Stream<AuthSession> watchSession();

  Future<AuthSession> get currentSession;

  Future<AuthSignUpResult> signUp(String email, String password);

  Future<void> confirmSignUp(String email, String code);

  Future<void> resendSignUpCode(String email);

  Future<void> signIn(String email, String password);

  Future<void> signOut();

  Future<void> beginPasswordReset(String email);

  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  );

  /// Returns a valid access token for internal HTTP transport only.
  ///
  /// UI code must never call or display this method's result. A forced refresh
  /// delegates refresh-token handling to the authentication SDK.
  Future<String> getValidAccessToken({bool forceRefresh = false});

  /// Invalidates local authentication after a terminal authorization failure.
  Future<void> invalidateSession();
}

/// Result of starting Cognito sign-up.
class AuthSignUpResult {
  const AuthSignUpResult({required this.confirmationRequired});

  final bool confirmationRequired;
}

/// Sanitized authentication failure categories exposed outside data code.
enum AuthFailureKind {
  invalidPassword,
  invalidCredentials,
  userNotConfirmed,
  invalidOrExpiredCode,
  userAlreadyExists,
  rateLimited,
  unavailable,
  unknown,
}

/// Authentication error containing no provider payload or sensitive input.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.safeMessage);

  final AuthFailureKind kind;
  final String safeMessage;

  @override
  String toString() => safeMessage;
}
