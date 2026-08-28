import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/app_version_provider.dart';
import 'package:interapp/core/push/installation_id_store.dart';
import 'package:interapp/core/push/push_installation_coordinator.dart';
import 'package:interapp/core/push/push_installation_repository.dart';
import 'package:interapp/core/push/push_providers.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';

class LifecycleAuth implements AuthRepository {
  LifecycleAuth() {
    sessions = StreamController<AuthSession>.broadcast(
      onListen: () => listenersCreated++,
      onCancel: () => listenersClosed++,
    );
  }

  late final StreamController<AuthSession> sessions;
  int listenersCreated = 0;
  int listenersClosed = 0;

  @override
  Stream<AuthSession> watchSession() => sessions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LifecycleIds implements InstallationIdStore {
  @override
  Future<String> getOrCreate() async =>
      '123e4567-e89b-42d3-a456-426614174000';
}

class LifecycleVersion implements AppVersionProvider {
  @override
  Future<String> load() async => '1.0.0+1';
}

class LifecyclePushRepository implements PushInstallationRepository {
  int registrations = 0;

  @override
  Future<void> deleteInstallation(String installationId) async {}

  @override
  Future<void> registerInstallation({
    required String installationId,
    required String token,
    required String appVersion,
  }) async {
    registrations++;
  }
}

void main() {
  test('integration owns one listener and stops reacting after disposal', () async {
    final auth = LifecycleAuth();
    final repository = LifecyclePushRepository();
    final coordinator = PushInstallationCoordinator(
      installationIds: LifecycleIds(),
      appVersions: LifecycleVersion(),
      repository: repository,
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pushInstallationCoordinatorProvider.overrideWithValue(
          Future.value(coordinator),
        ),
      ],
    );

    container.read(pushInstallationIntegrationProvider);
    container.read(pushInstallationIntegrationProvider);
    await Future<void>.delayed(Duration.zero);
    expect(auth.listenersCreated, 1);

    auth.sessions.add(const AuthSession.signedOut());
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(auth.listenersClosed, 1);

    auth.sessions.add(const AuthSession(isSignedIn: true));
    coordinator.acceptToken('after-dispose');
    await Future<void>.delayed(Duration.zero);
    await coordinator.idle;
    expect(repository.registrations, 0);
    await auth.sessions.close();
  });
}
