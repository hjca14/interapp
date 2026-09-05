import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/push/app_version_provider.dart';
import 'package:interapp/core/push/installation_id_store.dart';
import 'package:interapp/core/push/push_installation_coordinator.dart';
import 'package:interapp/core/push/push_installation_repository.dart';

class FakeIds implements InstallationIdStore {
  @override
  Future<String> getOrCreate() async => '123e4567-e89b-42d3-a456-426614174000';
}

class FakeVersion implements AppVersionProvider {
  @override
  Future<String> load() async => '1.0.0+1';
}

class FakePushRepository implements PushInstallationRepository {
  final tokens = <String>[];
  final errors = <Object>[];
  Completer<void>? gate;
  Object? deleteError;
  int deletes = 0;
  int active = 0;
  int maxActive = 0;
  @override
  Future<void> registerInstallation({
    required String installationId,
    required String token,
    required String appVersion,
  }) async {
    tokens.add(token);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (gate != null) await gate!.future;
      if (errors.isNotEmpty) throw errors.removeAt(0);
    } finally {
      active--;
    }
  }

  @override
  Future<void> deleteInstallation(String installationId) async {
    deletes++;
    if (deleteError != null) {
      throw deleteError!;
    }
  }
}

PushInstallationCoordinator coordinator(FakePushRepository repository) =>
    PushInstallationCoordinator(
      installationIds: FakeIds(),
      appVersions: FakeVersion(),
      repository: repository,
      delay: (_) async {},
    );

void main() {
  test(
    'token before session and session before token both synchronize',
    () async {
      for (final tokenFirst in [true, false]) {
        final repository = FakePushRepository();
        final value = coordinator(repository);
        if (tokenFirst) value.acceptToken('token');
        value.setAuthenticated(true);
        if (!tokenFirst) value.acceptToken('token');
        await value.idle;
        expect(repository.tokens, ['token']);
      }
    },
  );

  test(
    'login/restoration repairs once, duplicate token does not storm',
    () async {
      final repository = FakePushRepository();
      final value = coordinator(repository)..acceptToken('token');
      value.setAuthenticated(true);
      await value.idle;
      value.acceptToken('token');
      await value.idle;
      expect(repository.tokens, ['token']);
      value.setAuthenticated(false);
      value.setAuthenticated(true);
      await value.idle;
      expect(repository.tokens, ['token', 'token']);
    },
  );

  test('renewals serialize and latest token wins', () async {
    final repository = FakePushRepository()..gate = Completer<void>();
    final value = coordinator(repository)..setAuthenticated(true);
    value.acceptToken('one');
    await Future<void>.delayed(Duration.zero);
    value
      ..acceptToken('two')
      ..acceptToken('three');
    repository.gate!.complete();
    await value.idle;
    expect(repository.tokens, ['one', 'three']);
    expect(repository.maxActive, 1);
  });

  test(
    'temporary retry is bounded and permanent error does not loop',
    () async {
      final temporary = FakePushRepository()
        ..errors.addAll(
          List.filled(4, const ApiFailure(ApiFailureKind.offline, 'safe')),
        );
      final first = coordinator(temporary)
        ..setAuthenticated(true)
        ..acceptToken('token');
      await first.idle;
      expect(temporary.tokens.length, 3);

      final permanent = FakePushRepository()
        ..errors.add(const ApiFailure(ApiFailureKind.badRequest, 'safe'));
      final second = coordinator(permanent)
        ..setAuthenticated(true)
        ..acceptToken('token');
      await second.idle;
      expect(permanent.tokens.length, 1);
    },
  );

  test('logout waits for PUT and blocks refresh registration', () async {
    final repository = FakePushRepository()..gate = Completer<void>();
    final value = coordinator(repository)..setAuthenticated(true);
    value.acceptToken('before-logout');
    await Future<void>.delayed(Duration.zero);

    final logout = value.deleteForLogout();
    value.acceptToken('during-logout');
    await Future<void>.delayed(Duration.zero);
    expect(repository.deletes, 0, reason: 'DELETE must wait for the PUT');
    expect(repository.tokens, ['before-logout']);

    repository.gate!.complete();
    await logout;
    expect(repository.deletes, 1);
    await Future<void>.delayed(Duration.zero);
    expect(repository.tokens, [
      'before-logout',
    ], reason: 'no PUT may run after DELETE while logout is completing');
    value.completeLogout();
  });

  test(
    'DELETE failure removes barrier and permits later synchronization',
    () async {
      final repository = FakePushRepository();
      final value = coordinator(repository)
        ..setAuthenticated(true)
        ..acceptToken('initial');
      await value.idle;
      repository.deleteError = const ApiFailure(ApiFailureKind.offline, 'safe');

      await expectLater(value.deleteForLogout(), throwsA(isA<ApiFailure>()));
      repository.deleteError = null;
      value.acceptToken('after-failure');
      await value.idle;

      expect(repository.tokens, ['initial', 'after-failure']);
    },
  );
}
