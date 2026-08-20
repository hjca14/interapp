import 'dart:async';

import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

/// Deterministic [AuthRepository] fake intended only for explicit tests.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({
    AuthSession initial = const AuthSession.signedOut(),
    this.accessToken = 'test-access-token',
  }) : _session = initial;

  final _sessionChanges = StreamController<AuthSession>.broadcast();
  final String accessToken;
  AuthSession _session;

  @override
  Future<AuthSession> get currentSession async => _session;

  @override
  Stream<AuthSession> watchSession() async* {
    yield _session;
    yield* _sessionChanges.stream;
  }

  @override
  Future<AuthSignUpResult> signUp(String email, String password) async {
    return const AuthSignUpResult(confirmationRequired: true);
  }

  @override
  Future<void> confirmSignUp(String email, String code) async {}

  @override
  Future<void> resendSignUpCode(String email) async {}

  @override
  Future<void> signIn(String email, String password) async {
    _session = AuthSession(
      isSignedIn: true,
      userId: 'opaque-test-sub',
      email: email,
    );
    _sessionChanges.add(_session);
  }

  @override
  Future<void> signOut() => invalidateSession();

  @override
  Future<void> beginPasswordReset(String email) async {}

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {}

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    if (!_session.isSignedIn) {
      throw const AuthFailure(
        AuthFailureKind.invalidCredentials,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    return accessToken;
  }

  @override
  Future<void> invalidateSession() async {
    _session = const AuthSession.signedOut();
    _sessionChanges.add(_session);
  }
}
