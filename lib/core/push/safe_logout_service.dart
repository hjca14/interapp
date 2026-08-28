import '../../features/auth/domain/repositories/auth_repository.dart';
import 'push_installation_coordinator.dart';

/// Removes the authenticated push installation before ending the session.
class SafeLogoutService {
  SafeLogoutService(this._push, this._auth);
  final PushInstallationCoordinator _push;
  final AuthRepository _auth;

  Future<void> signOut() async {
    final session = await _auth.currentSession;
    if (!session.isSignedIn) {
      await _auth.invalidateSession();
      throw const AuthFailure(
        AuthFailureKind.sessionExpired,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    await _push.deleteForLogout();
    try {
      await _auth.signOut();
      _push.completeLogout();
    } on Object {
      _push.restoreAfterLogoutFailure();
      rethrow;
    }
  }
}
