import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/push/app_version_provider.dart';
import 'package:interapp/core/push/installation_id_store.dart';
import 'package:interapp/core/push/push_installation_coordinator.dart';
import 'package:interapp/core/push/push_installation_repository.dart';
import 'package:interapp/core/push/safe_logout_service.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

class LogoutIds implements InstallationIdStore {
  @override
  Future<String> getOrCreate() async => '123e4567-e89b-42d3-a456-426614174000';
}

class LogoutVersion implements AppVersionProvider {
  @override
  Future<String> load() async => '1.0.0+1';
}

class LogoutPushRepository implements PushInstallationRepository {
  LogoutPushRepository(this.events);
  final List<String> events;
  Object? deleteError;
  @override
  Future<void> deleteInstallation(String installationId) async {
    events.add('delete');
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<void> registerInstallation({
    required String installationId,
    required String token,
    required String appVersion,
  }) async {
    events.add('register');
  }
}

class LogoutAuth implements AuthRepository {
  LogoutAuth(this.events, {this.signedIn = true});
  final List<String> events;
  bool signedIn;
  bool invalidated = false;
  Object? signOutError;
  @override
  Future<AuthSession> get currentSession async =>
      AuthSession(isSignedIn: signedIn);
  @override
  Future<void> signOut() async {
    events.add('signOut');
    if (signOutError != null) {
      throw signOutError!;
    }
    signedIn = false;
  }

  @override
  Future<void> invalidateSession() async => invalidated = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PushInstallationCoordinator logoutCoordinator(
  PushInstallationRepository repository,
) => PushInstallationCoordinator(
  installationIds: LogoutIds(),
  appVersions: LogoutVersion(),
  repository: repository,
);

void main() {
  test('DELETE happens before sign-out and needs no token in memory', () async {
    final events = <String>[];
    final auth = LogoutAuth(events);
    await SafeLogoutService(
      logoutCoordinator(LogoutPushRepository(events)),
      auth,
    ).signOut();
    expect(events, ['delete', 'signOut']);
    expect(auth.signedIn, isFalse);
  });

  test('temporary DELETE failure prevents false logout and supports retry', () async {
    final events = <String>[];
    final auth = LogoutAuth(events);
    final repository = LogoutPushRepository(events)
      ..deleteError = const ApiFailure(ApiFailureKind.offline, 'safe');
    final service = SafeLogoutService(logoutCoordinator(repository), auth);
    await expectLater(service.signOut(), throwsA(isA<ApiFailure>()));
    expect(auth.signedIn, isTrue);
    expect(events, ['delete']);
    repository.deleteError = null;
    await service.signOut();
    expect(events, ['delete', 'delete', 'signOut']);
  });

  test('expired session follows central invalidation without DELETE', () async {
    final events = <String>[];
    final auth = LogoutAuth(events, signedIn: false);
    await expectLater(
      SafeLogoutService(
        logoutCoordinator(LogoutPushRepository(events)),
        auth,
      ).signOut(),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.invalidated, isTrue);
    expect(events, isEmpty);
  });

  test('Cognito failure after DELETE restores and repairs registration', () async {
    final events = <String>[];
    final auth = LogoutAuth(events)..signOutError = StateError('provider');
    final repository = LogoutPushRepository(events);
    final coordinator = logoutCoordinator(repository)
      ..setAuthenticated(true)
      ..acceptToken('private-token');
    await coordinator.idle;
    events.clear();

    await expectLater(
      SafeLogoutService(coordinator, auth).signOut(),
      throwsA(isA<StateError>()),
    );
    await coordinator.idle;

    expect(events, ['delete', 'signOut', 'register']);
    expect(auth.signedIn, isTrue);
  });
}
