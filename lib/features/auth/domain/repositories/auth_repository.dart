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

  /// Changes the password of the currently authenticated user, verifying
  /// [currentPassword] before applying [newPassword] via Cognito.
  ///
  /// Unlike [beginPasswordReset]/[confirmPasswordReset], this never signs the
  /// user out on success and requires no code — it is for a signed-in user
  /// who already knows their current password.
  Future<void> changePassword(String currentPassword, String newPassword);

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
  incorrectCurrentPassword,
  userNotConfirmed,
  invalidOrExpiredCode,
  userAlreadyExists,
  rateLimited,
  notAuthenticated,
  sessionExpired,
  unavailable,

  /// A password-reset-confirmation exception that cannot be detailed further
  /// without risking account-enumeration or reusing an unrelated context's
  /// message (e.g. login's "e-mail ou senha inválidos").
  invalidResetState,

  /// [AuthRepository.beginPasswordReset] reports the reset is already
  /// complete rather than requiring a confirmation code — not a real
  /// failure, but the only channel available to signal a different outcome
  /// than the common "a code was sent" path without widening this method's
  /// return type.
  passwordResetComplete,
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
