import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/devices/data/repositories/local_notification_preferences_outbox_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/notification_preferences_outbox_entry.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/repositories/notification_preferences_outbox_repository.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int activePatchCalls = 0;
  int maxActivePatchCalls = 0;
  final List<DeviceNotificationPreferences> patchedDrafts = [];
  final List<DeviceNotificationPreferences> patchedBaselines = [];

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
    activePatchCalls++;
    if (activePatchCalls > maxActivePatchCalls) {
      maxActivePatchCalls = activePatchCalls;
    }
    patchedBaselines.add(baseline);
    patchedDrafts.add(draft);
    if (patchError case final Object error) throw error;
    // A real server confirms exactly what it received (with a fresh
    // updatedAt); echoing `draft` here is far closer to that than always
    // returning the fixed `value`, which a test overrides explicitly via
    // `pendingPatch` whenever it needs a different confirmed response.
    try {
      return await (pendingPatch?.future ??
          Future.value(draft.copyWith(updatedAt: DateTime.utc(2026, 8, 27))));
    } finally {
      activePatchCalls--;
    }
  }
}

class _ControlledOutbox implements NotificationPreferencesOutboxRepository {
  NotificationPreferencesOutboxEntry? entry;
  int writeCalls = 0;
  int clearCalls = 0;
  Completer<void>? blockNextWrite;
  Completer<void>? blockNextClear;

  @override
  Future<NotificationPreferencesOutboxEntry?> read(
    String userId,
    String deviceId,
  ) async => entry;

  @override
  Future<void> write(
    String userId,
    String deviceId,
    NotificationPreferencesOutboxEntry value,
  ) async {
    writeCalls++;
    final blocker = blockNextWrite;
    blockNextWrite = null;
    if (blocker != null) await blocker.future;
    entry = value;
  }

  @override
  Future<void> clear(String userId, String deviceId) async {
    clearCalls++;
    final blocker = blockNextClear;
    blockNextClear = null;
    if (blocker != null) await blocker.future;
    entry = null;
  }
}

const _deviceId = 'device';
const _userId = 'user-1';
const _debounce = DeviceNotificationPreferencesController.debounceDuration;

ProviderContainer _containerFor(
  _Repository repository, {
  TimezoneLoader? timezoneLoader,
  LocalAuthRepository? auth,
  NotificationPreferencesOutboxRepository? outbox,
}) {
  final container = ProviderContainer(
    overrides: [
      deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
      if (timezoneLoader != null)
        timezoneLoaderProvider.overrideWithValue(timezoneLoader),
      if (outbox != null)
        notificationPreferencesOutboxRepositoryProvider.overrideWithValue(
          outbox,
        ),
      // `LocalAuthRepository.watchSession()` yields its current value
      // synchronously (an async* generator, not a raw controller-backed
      // stream), which resolves reliably under fakeAsync's microtask
      // scheduling — a directly-overridden `authSessionProvider` stream did
      // not.
      authRepositoryProvider.overrideWithValue(
        auth ??
            LocalAuthRepository(
              initial: const AuthSession(isSignedIn: true, userId: _userId),
            ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

NotificationPreferencesState _state(ProviderContainer container) =>
    container.read(deviceNotificationPreferencesProvider(_deviceId));

DeviceNotificationPreferencesController _controller(
  ProviderContainer container,
) => container.read(deviceNotificationPreferencesProvider(_deviceId).notifier);

void _load(FakeAsync async, ProviderContainer container) {
  // A one-off `container.read()` does not keep this Riverpod version's
  // Notifier reactive to its own internal `ref.listen` subscriptions (here,
  // the one watching `authSessionProvider` for the outbox's user id) — a
  // persistent `container.listen()` does, matching how a real widget would
  // continuously `ref.watch` this provider. The subscription is deliberately
  // never closed: it just needs to outlive the test, and container disposal
  // (via `addTearDown` in `_containerFor`) cleans it up.
  container.listen(deviceNotificationPreferencesProvider(_deviceId), (_, _) {});
  async.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initial loading, successful GET, and concurrent load limit', () {
    fakeAsync((async) {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingGet = pending;
      final container = _containerFor(repository);

      container.read(deviceNotificationPreferencesProvider(_deviceId));
      expect(_state(container).phase, NotificationPreferencesPhase.loading);

      final controller = _controller(container);
      final first = controller.load();
      final second = controller.load();
      async.flushMicrotasks();
      expect(repository.getCalls, 1);

      pending.complete(repository.value);
      async.flushMicrotasks();
      unawaited(first);
      unawaited(second);
      expect(_state(container).phase, NotificationPreferencesPhase.ready);
    });
  });

  test('initial error supports retry', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..getError = const ApiFailure(ApiFailureKind.offline, 'Sem conexão.');
      final container = _containerFor(repository);
      _load(async, container);
      expect(_state(container).phase, NotificationPreferencesPhase.loadError);

      repository.getError = null;
      unawaited(_controller(container).retry());
      async.flushMicrotasks();
      expect(_state(container).phase, NotificationPreferencesPhase.ready);
      expect(repository.getCalls, 2);
    });
  });

  test('debounce groups rapid edits into a single PATCH', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(const Duration(milliseconds: 200));
      controller.edit((v) => v.copyWith(alertMode: AlertMode.ringOnly));
      async.elapse(const Duration(milliseconds: 200));
      controller.edit((v) => v.copyWith(alertMode: AlertMode.notificationOnly));
      async.elapse(_debounce - const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repository.patchCalls, 0, reason: 'debounce has not fired yet');

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);
      expect(
        repository.patchedDrafts.single.alertMode,
        AlertMode.notificationOnly,
      );
    });
  });

  test('edit starts durable outbox persistence before the remote debounce', () {
    fakeAsync((async) {
      final blocker = Completer<void>();
      final outbox = _ControlledOutbox()..blockNextWrite = blocker;
      final repository = _Repository();
      final container = _containerFor(repository, outbox: outbox);
      _load(async, container);

      _controller(
        container,
      ).edit((value) => value.copyWith(alertMode: AlertMode.none));
      async.flushMicrotasks();

      expect(repository.patchCalls, 0);
      expect(outbox.writeCalls, 1, reason: 'local persistence starts at edit');
      expect(outbox.entry, isNull, reason: 'the controlled write is blocked');

      blocker.complete();
      async.flushMicrotasks();
      expect(outbox.entry!.pendingDraft.alertMode, AlertMode.none);
      expect(repository.patchCalls, 0, reason: '700 ms has not elapsed');
    });
  });

  test('abrupt disposal during debounce leaves the edit recoverable', () {
    fakeAsync((async) {
      final blocker = Completer<void>();
      final outbox = _ControlledOutbox()..blockNextWrite = blocker;
      final repository = _Repository();
      final container = _containerFor(repository, outbox: outbox);
      _load(async, container);

      _controller(
        container,
      ).edit((value) => value.copyWith(alertMode: AlertMode.none));
      async.flushMicrotasks();
      container.dispose();
      blocker.complete();
      async.flushMicrotasks();

      expect(repository.patchCalls, 0);
      expect(outbox.entry!.pendingDraft.alertMode, AlertMode.none);
    });
  });

  test('flush lock is held while the first local write is blocked', () {
    fakeAsync((async) {
      final blocker = Completer<void>();
      final outbox = _ControlledOutbox()..blockNextWrite = blocker;
      final repository = _Repository();
      final container = _containerFor(repository, outbox: outbox);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((value) => value.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      controller.flushPendingNow();
      async.flushMicrotasks();

      expect(repository.patchCalls, 0);
      blocker.complete();
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);
      expect(repository.maxActivePatchCalls, 1);
    });
  });

  test(
    'an edit queued behind a blocked clear survives and sends one delta',
    () {
      fakeAsync((async) {
        final outbox = _ControlledOutbox();
        final repository = _Repository();
        final container = _containerFor(repository, outbox: outbox);
        _load(async, container);
        final controller = _controller(container);

        controller.edit((value) => value.copyWith(alertMode: AlertMode.none));
        async.flushMicrotasks();
        final clearBlocker = Completer<void>();
        outbox.blockNextClear = clearBlocker;
        async.elapse(_debounce);
        async.flushMicrotasks();
        expect(repository.patchCalls, 1);
        expect(outbox.clearCalls, 1);

        controller.edit(
          (value) => value.copyWith(alertMode: AlertMode.ringOnly),
        );
        async.flushMicrotasks();
        expect(_state(container).draft!.alertMode, AlertMode.ringOnly);

        clearBlocker.complete();
        async.flushMicrotasks();
        expect(outbox.entry!.pendingDraft.alertMode, AlertMode.ringOnly);
        expect(_state(container).isSyncing, isTrue);

        async.elapse(_debounce);
        async.flushMicrotasks();
        expect(repository.patchCalls, 2);
        expect(repository.patchedDrafts.last.alertMode, AlertMode.ringOnly);
        expect(outbox.entry, isNull);
        expect(_state(container).isSyncing, isFalse);
      });
    },
  );

  test('an edit during a blocked post-response write is never overwritten', () {
    fakeAsync((async) {
      final outbox = _ControlledOutbox();
      final response = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = response;
      final container = _containerFor(repository, outbox: outbox);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((value) => value.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);

      controller.edit((value) => value.copyWith(alertMode: AlertMode.ringOnly));
      async.flushMicrotasks();
      final postResponseBlocker = Completer<void>();
      outbox.blockNextWrite = postResponseBlocker;
      response.complete(
        DeviceNotificationPreferences(
          alertMode: AlertMode.none,
          updatedAt: DateTime.utc(2026, 8, 28),
        ),
      );
      async.flushMicrotasks();

      controller.edit(
        (value) => value.copyWith(alertMode: AlertMode.ringAndNotification),
      );
      async.flushMicrotasks();
      expect(_state(container).draft!.alertMode, AlertMode.ringAndNotification);

      postResponseBlocker.complete();
      async.flushMicrotasks();
      expect(
        outbox.entry!.pendingDraft.alertMode,
        AlertMode.ringAndNotification,
      );
      expect(_state(container).draft!.alertMode, AlertMode.ringAndNotification);
    });
  });

  test('several weekday selections produce a single PATCH', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      void toggleDay(int day) {
        controller.edit((v) {
          final days = Set<int>.from(v.quietSchedule.days)..add(day);
          return v.copyWith(
            quietSchedule: v.quietSchedule.copyWith(
              enabled: true,
              timezone: v.quietSchedule.timezone ?? 'America/Recife',
              days: days,
              startTime: ClockTime(hour: 22, minute: 0),
              endTime: ClockTime(hour: 7, minute: 0),
            ),
          );
        });
      }

      toggleDay(1);
      toggleDay(2);
      toggleDay(3);
      async.elapse(_debounce);
      async.flushMicrotasks();

      expect(repository.patchCalls, 1);
      expect(repository.patchedDrafts.single.quietSchedule.days, {1, 2, 3});
    });
  });

  test('identical final state never sends a PATCH', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);
      final originalMode = _state(container).draft!.alertMode;

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      controller.edit((v) => v.copyWith(alertMode: originalMode));
      async.elapse(_debounce);
      async.flushMicrotasks();

      expect(repository.patchCalls, 0);
      expect(_state(container).hasChanges, isFalse);
      expect(_state(container).isSyncing, isFalse);
    });
  });

  test('an empty PATCH is never sent', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      // No edit at all: nothing should ever be scheduled or sent.
      controller.edit((v) => v);
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 0);
    });
  });

  test('only one PATCH is ever active at a time', () {
    fakeAsync((async) {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = pending;
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);
      expect(_state(container).phase, NotificationPreferencesPhase.saving);

      // Edits while the PATCH is in flight must not start a second one.
      controller.edit((v) => v.copyWith(alertMode: AlertMode.ringOnly));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);
    });
  });

  test('editing during an in-flight PATCH is never blocked', () {
    fakeAsync((async) {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = pending;
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(_state(container).phase, NotificationPreferencesPhase.saving);
      expect(_state(container).canEdit, isTrue);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.ringOnly));
      expect(_state(container).draft!.alertMode, AlertMode.ringOnly);
    });
  });

  test('a stale in-flight response never overwrites a newer draft, and the '
      'remaining delta is sent as a single follow-up PATCH', () {
    fakeAsync((async) {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = pending;
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);

      // Edited again mid-flight — this must win once the response lands.
      controller.edit((v) => v.copyWith(alertMode: AlertMode.ringOnly));

      pending.complete(
        DeviceNotificationPreferences(
          alertMode: AlertMode.none,
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      async.flushMicrotasks();
      expect(
        _state(container).draft!.alertMode,
        AlertMode.ringOnly,
        reason: 'the stale response must not overwrite the newer edit',
      );
      expect(
        _state(container).baseline!.alertMode,
        AlertMode.none,
        reason: 'the baseline still reflects what the server confirmed',
      );
      expect(_state(container).hasChanges, isTrue);
      expect(
        repository.patchCalls,
        1,
        reason: 'the follow-up must wait for its own debounce window',
      );

      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 2);
      expect(repository.patchedDrafts.last.alertMode, AlertMode.ringOnly);
      expect(
        repository.patchedBaselines.last.alertMode,
        AlertMode.none,
        reason: 'the second PATCH is computed against the new baseline',
      );
    });
  });

  test('convergence settles into "Tudo salvo" (no changes, not syncing)', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();

      final state = _state(container);
      expect(state.hasChanges, isFalse);
      expect(state.isSyncing, isFalse);
      expect(state.phase, NotificationPreferencesPhase.ready);
    });
  });

  test('a recoverable failure preserves the draft and the outbox', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();

      expect(_state(container).phase, NotificationPreferencesPhase.saveError);
      expect(_state(container).draft!.alertMode, AlertMode.none);
      expect(_state(container).canEdit, isTrue);

      final outbox = LocalNotificationPreferencesOutboxRepository();
      NotificationPreferencesOutboxEntry? entry;
      unawaited(outbox.read(_userId, _deviceId).then((value) => entry = value));
      async.flushMicrotasks();
      expect(entry, isNotNull);
      expect(entry!.pendingDraft.alertMode, AlertMode.none);
    });
  });

  test('manual retry resumes a failed autosave', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(_state(container).phase, NotificationPreferencesPhase.saveError);
      expect(repository.patchCalls, 1);

      repository.patchError = null;
      unawaited(controller.retry());
      async.flushMicrotasks();

      expect(repository.patchCalls, 2);
      expect(_state(container).phase, NotificationPreferencesPhase.ready);
      expect(_state(container).hasChanges, isFalse);
    });
  });

  test('a 409 conflict never loops and resolves with one GET', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.conflict, 'Conflict');
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);
      final getCallsBefore = repository.getCalls;

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();

      expect(_state(container).phase, NotificationPreferencesPhase.conflict);
      expect(
        repository.getCalls,
        getCallsBefore + 1,
        reason: 'exactly one reconciliation GET, never a loop',
      );
      expect(repository.patchCalls, 1);
      expect(_state(container).draft!.alertMode, AlertMode.none);
    });
  });

  test(
    'a conflict that already matches the draft resolves silently as synced',
    () {
      fakeAsync((async) {
        final repository = _Repository()
          ..patchError = const ApiFailure(ApiFailureKind.conflict, 'Conflict');
        final container = _containerFor(repository);
        _load(async, container);
        final controller = _controller(container);

        controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
        // The server already has this value by the time we reconcile.
        repository.value = DeviceNotificationPreferences(
          alertMode: AlertMode.none,
          updatedAt: DateTime.utc(2026, 8, 27),
        );
        async.elapse(_debounce);
        async.flushMicrotasks();

        expect(_state(container).phase, NotificationPreferencesPhase.ready);
        expect(_state(container).hasChanges, isFalse);
      });
    },
  );

  test('session expiration stops autosave and clears this outbox entry', () {
    fakeAsync((async) {
      final repository = _Repository()
        ..patchError = const ApiFailure(
          ApiFailureKind.unauthorized,
          'Sessão expirada',
        );
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();

      expect(
        _state(container).phase,
        NotificationPreferencesPhase.sessionExpired,
      );

      final outbox = LocalNotificationPreferencesOutboxRepository();
      NotificationPreferencesOutboxEntry? entry;
      unawaited(outbox.read(_userId, _deviceId).then((value) => entry = value));
      async.flushMicrotasks();
      expect(entry, isNull);
    });
  });

  test('a disposed controller never applies a response that arrives after', () {
    fakeAsync((async) {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = pending;
      final container = ProviderContainer(
        overrides: [
          deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
            repository,
          ),
          authSessionProvider.overrideWith(
            (ref) => Stream.value(
              const AuthSession(isSignedIn: true, userId: _userId),
            ),
          ),
        ],
      );
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 1);

      container.dispose();
      pending.complete(
        DeviceNotificationPreferences(
          alertMode: AlertMode.none,
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      expect(() => async.flushMicrotasks(), returnsNormally);
    });
  });

  test('logout clears this device\'s outbox entry for that user while this '
      'device\'s controller is being watched (e.g. its page is open)', () {
    fakeAsync((async) {
      final auth = LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true, userId: _userId),
      );
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      final container = _containerFor(repository, auth: auth);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(_state(container).phase, NotificationPreferencesPhase.saveError);

      unawaited(auth.signOut());
      async.flushMicrotasks();

      final outbox = LocalNotificationPreferencesOutboxRepository();
      NotificationPreferencesOutboxEntry? entry;
      unawaited(outbox.read(_userId, _deviceId).then((value) => entry = value));
      async.flushMicrotasks();
      expect(entry, isNull);
    });
  });

  test('a pending entry from another user is never applied', () {
    fakeAsync((async) {
      final outbox = LocalNotificationPreferencesOutboxRepository();
      unawaited(
        outbox.write(
          'someone-else',
          _deviceId,
          NotificationPreferencesOutboxEntry(
            pendingDraft: DeviceNotificationPreferences(
              alertMode: AlertMode.none,
            ),
            baselineUpdatedAt: null,
          ),
        ),
      );
      async.flushMicrotasks();

      final repository = _Repository(
        value: DeviceNotificationPreferences(
          alertMode: AlertMode.ringAndNotification,
        ),
      );
      final container = _containerFor(repository);
      _load(async, container);

      expect(_state(container).draft!.alertMode, AlertMode.ringAndNotification);
      expect(_state(container).hasChanges, isFalse);
    });
  });

  test('reopening resumes a still-valid pending entry from this user', () {
    fakeAsync((async) {
      final baseline = DeviceNotificationPreferences(
        alertMode: AlertMode.ringAndNotification,
        updatedAt: DateTime.utc(2026, 8, 27),
      );
      final outbox = LocalNotificationPreferencesOutboxRepository();
      unawaited(
        outbox.write(
          _userId,
          _deviceId,
          NotificationPreferencesOutboxEntry(
            pendingDraft: DeviceNotificationPreferences(
              alertMode: AlertMode.none,
            ),
            baselineUpdatedAt: baseline.updatedAt,
          ),
        ),
      );
      async.flushMicrotasks();

      // Held open so the resume attempt's intermediate state (resumed draft,
      // still-unconfirmed baseline) can be observed before it converges.
      final pendingResume = Completer<DeviceNotificationPreferences>();
      final repository = _Repository(value: baseline)
        ..pendingPatch = pendingResume;
      final container = _containerFor(repository);
      _load(async, container);

      expect(
        _state(container).draft!.alertMode,
        AlertMode.none,
        reason: 'the pending edit is resumed as the draft',
      );
      expect(
        _state(container).baseline!.alertMode,
        AlertMode.ringAndNotification,
        reason: 'the baseline is what the server actually has right now',
      );
      expect(
        repository.patchCalls,
        1,
        reason: 'the reopen flow attempts a best-effort resume immediately',
      );

      pendingResume.complete(
        DeviceNotificationPreferences(
          alertMode: AlertMode.none,
          updatedAt: DateTime.utc(2026, 8, 28),
        ),
      );
      async.flushMicrotasks();
      expect(_state(container).hasChanges, isFalse);

      final entry = <NotificationPreferencesOutboxEntry?>[null];
      unawaited(outbox.read(_userId, _deviceId).then((v) => entry[0] = v));
      async.flushMicrotasks();
      expect(entry[0], isNull);
    });
  });

  test('a server value already equal to the pending entry clears it without a '
      'new PATCH', () {
    fakeAsync((async) {
      final confirmed = DeviceNotificationPreferences(
        alertMode: AlertMode.none,
        updatedAt: DateTime.utc(2026, 8, 27),
      );
      final outbox = LocalNotificationPreferencesOutboxRepository();
      unawaited(
        outbox.write(
          _userId,
          _deviceId,
          NotificationPreferencesOutboxEntry(
            pendingDraft: DeviceNotificationPreferences(
              alertMode: AlertMode.none,
            ),
            baselineUpdatedAt: DateTime.utc(2026, 8, 20),
          ),
        ),
      );
      async.flushMicrotasks();

      final repository = _Repository(value: confirmed);
      final container = _containerFor(repository);
      _load(async, container);

      expect(_state(container).hasChanges, isFalse);
      expect(_state(container).draft!.alertMode, AlertMode.none);
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(
        repository.patchCalls,
        0,
        reason: 'already applied server-side, nothing left to send',
      );

      NotificationPreferencesOutboxEntry? entry;
      unawaited(outbox.read(_userId, _deviceId).then((value) => entry = value));
      async.flushMicrotasks();
      expect(entry, isNull);
    });
  });

  test(
    'an incompatible server change on reopen is surfaced, not overwritten',
    () {
      fakeAsync((async) {
        final outbox = LocalNotificationPreferencesOutboxRepository();
        unawaited(
          outbox.write(
            _userId,
            _deviceId,
            NotificationPreferencesOutboxEntry(
              pendingDraft: DeviceNotificationPreferences(
                alertMode: AlertMode.none,
              ),
              baselineUpdatedAt: DateTime.utc(2026, 8, 20),
            ),
          ),
        );
        async.flushMicrotasks();

        // Server moved on to a value with a different updatedAt and
        // different editable values than what our pending edit expected.
        final repository = _Repository(
          value: DeviceNotificationPreferences(
            alertMode: AlertMode.ringOnly,
            updatedAt: DateTime.utc(2026, 8, 26),
          ),
        );
        final container = _containerFor(repository);
        _load(async, container);

        expect(_state(container).phase, NotificationPreferencesPhase.saveError);
        expect(_state(container).draft!.alertMode, AlertMode.none);
        expect(_state(container).baseline!.alertMode, AlertMode.ringOnly);
      });
    },
  );

  test('closing during the debounce window does not lose the edit', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit((v) => v.copyWith(alertMode: AlertMode.none));
      expect(repository.patchCalls, 0);

      // Simulates NotificationPreferencesPage.dispose()'s best-effort flush.
      controller.flushPendingNow();
      async.flushMicrotasks();

      expect(repository.patchCalls, 1);
      expect(repository.patchedDrafts.single.alertMode, AlertMode.none);
    });
  });

  test('dirty state ignores read-only fields and an edit that reverts to the '
      'baseline is inert', () {
    fakeAsync((async) {
      final repository = _Repository(
        value: DeviceNotificationPreferences(
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      );
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      controller.edit(
        (value) =>
            value.copyWith(version: 2, updatedAt: DateTime.utc(2026, 8, 28)),
      );
      expect(_state(container).hasChanges, isFalse);
      async.elapse(_debounce);
      async.flushMicrotasks();
      expect(repository.patchCalls, 0);
    });
  });

  test('reset defaults is inert when already default, and a changed reset '
      'preserves read-only fields', () {
    fakeAsync((async) {
      final timestamp = DateTime.utc(2026, 8, 27);
      final defaults = DeviceNotificationPreferences(updatedAt: timestamp);
      final repository = _Repository(value: defaults);
      final container = _containerFor(repository);
      _load(async, container);
      final controller = _controller(container);

      unawaited(controller.resetRemote());
      async.flushMicrotasks();
      expect(repository.patchCalls, 0);

      final changed = DeviceNotificationPreferences(
        alertMode: AlertMode.none,
        updatedAt: timestamp,
      );
      repository.value = changed;
      unawaited(controller.load());
      async.flushMicrotasks();
      repository.value = defaults;
      unawaited(controller.resetRemote());
      async.flushMicrotasks();

      expect(repository.patchCalls, 1);
      expect(
        repository.patchedDrafts.single.alertMode,
        AlertMode.ringAndNotification,
      );
      expect(repository.patchedDrafts.single.quietSchedule, QuietSchedule());
      expect(repository.patchedDrafts.single.updatedAt, timestamp);
    });
  });

  test('timezone is loaded once and a persisted timezone is preserved', () {
    fakeAsync((async) {
      var timezoneCalls = 0;
      final repository = _Repository();
      final container = _containerFor(
        repository,
        timezoneLoader: () async {
          timezoneCalls++;
          return 'America/Recife';
        },
      );
      _load(async, container);
      final controller = _controller(container);

      unawaited(controller.enableSchedule(true));
      async.flushMicrotasks();
      expect(timezoneCalls, 1);
      expect(_state(container).draft!.quietSchedule.timezone, 'America/Recife');

      controller.edit(
        (value) => value.copyWith(
          quietSchedule: value.quietSchedule.copyWith(enabled: false),
        ),
      );
      unawaited(controller.enableSchedule(true));
      async.flushMicrotasks();
      expect(timezoneCalls, 1);
    });
  });

  test('timezone failure is specific and keeps remote values editable', () {
    fakeAsync((async) {
      final repository = _Repository();
      final container = _containerFor(
        repository,
        timezoneLoader: () async => throw const TimezoneUnavailableException(),
      );
      _load(async, container);

      unawaited(_controller(container).enableSchedule(true));
      async.flushMicrotasks();

      final state = _state(container);
      expect(state.phase, NotificationPreferencesPhase.ready);
      expect(state.timezoneError, contains('fuso horário'));
      expect(state.draft!.quietSchedule.enabled, isFalse);
      expect(state.canEdit, isTrue);
    });
  });
}
