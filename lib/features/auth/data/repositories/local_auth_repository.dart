import 'dart:async';

import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

/// Deterministic [AuthRepository] fake intended only for explicit tests.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({
    AuthSession initial = const AuthSession.signedOut(),
    this.accessToken = 'test-access-token',
    this.changePasswordFailure,
  }) : _session = initial;

  final _sessionChanges = StreamController<AuthSession>.broadcast();
  final String accessToken;
  AuthSession _session;

  /// Set by a test to make the next [changePassword] call fail with this
  /// failure instead of succeeding. Left in place across calls so a test can
  /// clear it to simulate a corrected retry.
  AuthFailure? changePasswordFailure;
  String? lastChangePasswordCurrent;
  String? lastChangePasswordNew;

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
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    lastChangePasswordCurrent = currentPassword;
    lastChangePasswordNew = newPassword;
    final failure = changePasswordFailure;
    if (failure == null) {
      return;
    }
    if (failure.kind == AuthFailureKind.sessionExpired ||
        failure.kind == AuthFailureKind.notAuthenticated) {
      await invalidateSession();
    }
    throw failure;
  }

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
