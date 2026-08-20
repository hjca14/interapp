/// Minimal human session exposed to application code.
///
/// Cognito tokens and passwords deliberately do not belong to this entity.
class AuthSession {
  const AuthSession({required this.isSignedIn, this.userId, this.email});

  const AuthSession.signedOut()
    : isSignedIn = false,
      userId = null,
      email = null;

  final bool isSignedIn;
  final String? userId;
  final String? email;
}
