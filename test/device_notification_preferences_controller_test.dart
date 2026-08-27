import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

class _Repository implements DeviceNotificationPreferencesRepository {
  _Repository({DeviceNotificationPreferences? value})
    : value = value ?? DeviceNotificationPreferences();

  DeviceNotificationPreferences value;
  Object? getError;
  Object? patchError;
  Completer<DeviceNotificationPreferences>? pendingGet;
  Completer<DeviceNotificationPreferences>? pendingPatch;
  int getCalls = 0;
  int patchCalls = 0;
  DeviceNotificationPreferences? patchedDraft;

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async {
    getCalls++;
    if (getError case final Object error) throw error;
    return pendingGet?.future ?? value;
  }

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    patchCalls++;
    patchedDraft = draft;
    if (patchError case final Object error) throw error;
    return pendingPatch?.future ?? value;
  }
}

ProviderContainer _containerFor(
  _Repository repository, {
  TimezoneLoader? timezoneLoader,
}) {
  final container = ProviderContainer(
    overrides: [
      deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
      if (timezoneLoader != null)
        timezoneLoaderProvider.overrideWithValue(timezoneLoader),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  const deviceId = 'device';

  test('initial loading, successful GET, and concurrent load limit', () async {
    final pending = Completer<DeviceNotificationPreferences>();
    final repository = _Repository()..pendingGet = pending;
    final container = _containerFor(repository);
    final provider = deviceNotificationPreferencesProvider(deviceId);

    expect(
      container.read(provider).phase,
      NotificationPreferencesPhase.loading,
    );
    await flush();
    final controller = container.read(provider.notifier);
    final first = controller.load();
    final second = controller.load();
    expect(repository.getCalls, 1);

    pending.complete(repository.value);
    await Future.wait([first, second]);
    expect(container.read(provider).phase, NotificationPreferencesPhase.ready);
  });

  test('initial error supports retry', () async {
    final repository = _Repository()
      ..getError = const ApiFailure(ApiFailureKind.offline, 'Sem conexão.');
    final container = _containerFor(repository);
    final provider = deviceNotificationPreferencesProvider(deviceId);
    container.read(provider);
    await flush();
    expect(
      container.read(provider).phase,
      NotificationPreferencesPhase.loadError,
    );

    repository.getError = null;
    await container.read(provider.notifier).load();
    expect(container.read(provider).phase, NotificationPreferencesPhase.ready);
    expect(repository.getCalls, 2);
  });

  test(
    'dirty state ignores read-only fields and save without changes is inert',
    () async {
      final repository = _Repository(
        value: DeviceNotificationPreferences(
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      final container = _containerFor(repository);
      final provider = deviceNotificationPreferencesProvider(deviceId);
      container.read(provider);
      await flush();
      final controller = container.read(provider.notifier);

      controller.edit(
        (value) =>
            value.copyWith(version: 2, updatedAt: DateTime.utc(2026, 8, 28)),
      );
      expect(container.read(provider).hasChanges, isFalse);
      expect(container.read(provider).canSave, isFalse);
      await controller.save();
      expect(repository.patchCalls, 0);
    },
  );

  test(
    'save is single-flight and server representation replaces draft',
    () async {
      final confirmed = DeviceNotificationPreferences(
        alertMode: AlertMode.none,
        updatedAt: DateTime.utc(2026, 8, 27),
      );
      final pending = Completer<DeviceNotificationPreferences>();
      // Baseline (returned by GET) deliberately differs from `confirmed` (what
      // the server returns from PATCH) so editing to AlertMode.none is an
      // actual change — otherwise `save()` would legitimately no-op.
      final repository = _Repository()..pendingPatch = pending;
      final container = _containerFor(repository);
      final provider = deviceNotificationPreferencesProvider(deviceId);
      container.read(provider);
      await flush();
      final controller = container.read(provider.notifier);
      controller.edit((value) => value.copyWith(alertMode: AlertMode.none));

      final first = controller.save();
      final second = controller.save();
      expect(
        container.read(provider).phase,
        NotificationPreferencesPhase.saving,
      );
      expect(repository.patchCalls, 1);
      pending.complete(confirmed);
      await Future.wait([first, second]);

      final state = container.read(provider);
      expect(state.phase, NotificationPreferencesPhase.saved);
      expect(state.message, 'Preferências salvas.');
      expect(state.baseline, same(confirmed));
      expect(state.draft, same(confirmed));
      expect(state.canSave, isFalse);
    },
  );

  test('recoverable save error and conflict preserve draft', () async {
    final repository = _Repository();
    final container = _containerFor(repository);
    final provider = deviceNotificationPreferencesProvider(deviceId);
    container.read(provider);
    await flush();
    final controller = container.read(provider.notifier);
    controller.edit((value) => value.copyWith(alertMode: AlertMode.none));
    final draft = container.read(provider).draft;

    repository.patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
    await controller.save();
    expect(
      container.read(provider).phase,
      NotificationPreferencesPhase.saveError,
    );
    expect(container.read(provider).draft, same(draft));
    expect(container.read(provider).canSave, isTrue);

    repository.patchError = const ApiFailure(
      ApiFailureKind.conflict,
      'Conflict',
    );
    await controller.save();
    expect(
      container.read(provider).phase,
      NotificationPreferencesPhase.conflict,
    );
    expect(container.read(provider).draft, same(draft));
    expect(container.read(provider).canSave, isFalse);
  });

  test('session expiration prevents editing and saving', () async {
    final repository = _Repository();
    final container = _containerFor(repository);
    final provider = deviceNotificationPreferencesProvider(deviceId);
    container.read(provider);
    await flush();
    final controller = container.read(provider.notifier);
    controller.edit((value) => value.copyWith(alertMode: AlertMode.none));
    repository.patchError = const ApiFailure(
      ApiFailureKind.unauthorized,
      'Sessão expirada',
    );
    await controller.save();
    expect(
      container.read(provider).phase,
      NotificationPreferencesPhase.sessionExpired,
    );
    expect(container.read(provider).canSave, isFalse);
    controller.edit((value) => value.copyWith(alertMode: AlertMode.ringOnly));
    expect(container.read(provider).draft!.alertMode, AlertMode.none);
  });

  test(
    'reset defaults is inert and changed reset preserves read-only fields',
    () async {
      final timestamp = DateTime.utc(2026, 8, 27);
      final defaults = DeviceNotificationPreferences(updatedAt: timestamp);
      final repository = _Repository(value: defaults);
      final container = _containerFor(repository);
      final provider = deviceNotificationPreferencesProvider(deviceId);
      container.read(provider);
      await flush();
      final controller = container.read(provider.notifier);

      await controller.resetRemote();
      expect(repository.patchCalls, 0);

      final changed = DeviceNotificationPreferences(
        alertMode: AlertMode.none,
        updatedAt: timestamp,
      );
      repository.value = changed;
      await controller.load();
      repository.value = defaults;
      await controller.resetRemote();
      expect(repository.patchCalls, 1);
      expect(repository.patchedDraft!.alertMode, AlertMode.ringAndNotification);
      expect(repository.patchedDraft!.quietSchedule, QuietSchedule());
      expect(repository.patchedDraft!.updatedAt, timestamp);
    },
  );

  test('timezone is loaded once and persisted timezone is preserved', () async {
    var timezoneCalls = 0;
    final repository = _Repository();
    final container = _containerFor(
      repository,
      timezoneLoader: () async {
        timezoneCalls++;
        return 'America/Recife';
      },
    );
    final provider = deviceNotificationPreferencesProvider(deviceId);
    container.read(provider);
    await flush();
    final controller = container.read(provider.notifier);

    await controller.enableSchedule(true);
    expect(timezoneCalls, 1);
    expect(
      container.read(provider).draft!.quietSchedule.timezone,
      'America/Recife',
    );
    controller.edit(
      (value) => value.copyWith(
        quietSchedule: value.quietSchedule.copyWith(enabled: false),
      ),
    );
    await controller.enableSchedule(true);
    expect(timezoneCalls, 1);
  });

  test(
    'timezone failure is specific and keeps remote values editable',
    () async {
      final repository = _Repository();
      final container = _containerFor(
        repository,
        timezoneLoader: () async => throw const TimezoneUnavailableException(),
      );
      final provider = deviceNotificationPreferencesProvider(deviceId);
      container.read(provider);
      await flush();

      await container.read(provider.notifier).enableSchedule(true);
      final state = container.read(provider);
      expect(state.phase, NotificationPreferencesPhase.ready);
      expect(state.timezoneError, contains('fuso horário'));
      expect(state.draft!.quietSchedule.enabled, isFalse);
      expect(state.canEdit, isTrue);
    },
  );
}
