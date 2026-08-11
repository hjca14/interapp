import 'package:interapp/features/auth/domain/entities/auth_session.dart';

/// Contract for human authentication against the application backend.
///
/// The decision leans toward Amazon Cognito (§27 of
/// `docs/communication-protocol.md`), but no widget/controller should
/// depend on a Cognito SDK directly — everything goes through this
/// abstraction instead, the same way device transport goes through
/// `DeviceConnectionRepository`.
///
/// Entirely separate from device authentication: this identifies a human
/// user to the backend; device X.509/mTLS identifies a physical InterBridge
/// to AWS IoT Core. Neither substitutes for the other.
abstract class AuthRepository {
  /// The current session, or `null` when signed out. Updates whenever
  /// sign-in state changes.
  Stream<AuthSession?> watchSession();

  Future<AuthSession?> get currentSession;

  Future<void> signIn();

  Future<void> signOut();
}
