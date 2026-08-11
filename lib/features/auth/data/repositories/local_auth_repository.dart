import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

/// Temporary implementation used until Cognito (or another provider) is
/// configured. Always reports "signed out" — it never fabricates a session.
///
/// Nothing in the app currently calls [signIn]/[signOut]: today's local
/// "profile" (`features/profile`, just a display name typed in on first
/// launch) is a separate, pre-existing concept from this future human-auth
/// layer and is intentionally left as-is by this task.
class LocalAuthRepository implements AuthRepository {
  @override
  Future<AuthSession?> get currentSession async => null;

  @override
  Stream<AuthSession?> watchSession() => Stream.value(null);

  @override
  Future<void> signIn() {
    throw UnsupportedError(
      'Human authentication (Cognito) is not configured yet.',
    );
  }

  @override
  Future<void> signOut() async {}
}
