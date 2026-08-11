/// A signed-in human user's session.
///
/// Deliberately minimal — human authentication (§27 of the protocol,
/// candidate: Cognito) is entirely separate from device X.509
/// authentication, and the app has no configured auth provider yet, so
/// there is nothing here beyond identifying who is signed in.
class AuthSession {
  const AuthSession({required this.userId, this.displayName});

  final String userId;
  final String? displayName;
}
