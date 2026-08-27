import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/notification_preferences_outbox_entry.dart';
import 'package:interapp/features/devices/domain/repositories/notification_preferences_outbox_repository.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

enum NotificationPreferencesPhase {
  loading,
  ready,
  resolvingTimezone,
  saving,
  loadError,
  saveError,
  conflict,
  sessionExpired,
}

/// Autosave state: [baseline] is the last server-confirmed representation,
/// [draft] is the latest user choice. Whenever they differ there is
/// unconfirmed work in flight, about to be sent, or queued locally — the UI
/// derives "Salvando..." vs "Tudo salvo" from [hasChanges] and [isSaving]
/// rather than from a one-shot "saved" flag, since autosave has no single
/// moment of "done" the way a Save button did.
class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.phase = NotificationPreferencesPhase.loading,
    this.baseline,
    this.draft,
    this.message,
    this.timezoneError,
  });

  final NotificationPreferencesPhase phase;
  final DeviceNotificationPreferences? baseline;
  final DeviceNotificationPreferences? draft;
  final String? message;
  final String? timezoneError;

  bool get hasChanges =>
      baseline != null &&
      draft != null &&
      !baseline!.hasSameEditableValues(draft!);

  bool get isSaving => phase == NotificationPreferencesPhase.saving;

  /// True whenever autosave has not yet converged: a debounce window is
  /// open, a PATCH is in flight, or a follow-up is queued. All three shapes
  /// show as "Salvando...", never as a distinct sub-state.
  bool get isSyncing => isSaving || hasChanges;

  bool get canEdit =>
      draft != null &&
      phase != NotificationPreferencesPhase.loading &&
      phase != NotificationPreferencesPhase.sessionExpired;

  bool get canReset => canEdit && baseline != null;

  bool get canRetry =>
      phase == NotificationPreferencesPhase.saveError ||
      phase == NotificationPreferencesPhase.conflict ||
      phase == NotificationPreferencesPhase.loadError;

  NotificationPreferencesState copyWith({
    NotificationPreferencesPhase? phase,
    DeviceNotificationPreferences? baseline,
    DeviceNotificationPreferences? draft,
    Object? message = _unset,
    Object? timezoneError = _unset,
  }) {
    return NotificationPreferencesState(
      phase: phase ?? this.phase,
      baseline: baseline ?? this.baseline,
      draft: draft ?? this.draft,
      message: identical(message, _unset) ? this.message : message as String?,
      timezoneError: identical(timezoneError, _unset)
          ? this.timezoneError
          : timezoneError as String?,
    );
  }
}

typedef TimezoneLoader = Future<String> Function();

final timezoneLoaderProvider = Provider<TimezoneLoader>((_) {
  return () async {
    try {
      const channel = MethodChannel('interapp/device_timezone');
      final identifier = await channel.invokeMethod<String>('getIdentifier');
      if (identifier == null || identifier.trim().isEmpty) {
        throw const TimezoneUnavailableException();
      }
      return identifier;
    } on TimezoneUnavailableException {
      rethrow;
    } on Object {
      throw const TimezoneUnavailableException();
    }
  };
});

class TimezoneUnavailableException implements Exception {
  const TimezoneUnavailableException();
}

class DeviceNotificationPreferencesController
    extends Notifier<NotificationPreferencesState> {
  DeviceNotificationPreferencesController(this.deviceId);

  final String deviceId;

  /// Groups rapid edits (e.g. dragging through weekday chips) into one
  /// PATCH instead of one per toggle.
  static const debounceDuration = Duration(milliseconds: 700);

  Future<void>? _activeLoad;
  int _generation = 0;
  bool _disposed = false;
  bool _saving = false;
  Timer? _debounceTimer;

  @override
  NotificationPreferencesState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _debounceTimer?.cancel();
    });
    // The outbox is a sync-intent cache scoped to one authenticated user; it
    // must never survive into a different session on the same device.
    //
    // Scoping note: like any non-autoDispose Notifier's internal `ref.listen`
    // in this Riverpod version, this only reacts while something is actively
    // watching this exact `deviceNotificationPreferencesProvider(deviceId)`
    // (i.e. `NotificationPreferencesPage` for this device is open) — Riverpod
    // does not keep reactively ticking a provider nobody watches, even
    // though its state and this subscription remain mounted. If the user
    // logs out from elsewhere while this device's page isn't open, a pending
    // entry is not proactively cleared; it stays inert (never applied to a
    // different account, since it is keyed by this device *and* the user id
    // that wrote it) and self-cleans the next time this same user reopens
    // this device's notifications page — the "Ao reabrir" reconciliation in
    // `_reconcileOnLoad` clears or safely merges it then. A guaranteed,
    // proactive sweep across every device on global logout would require
    // hooking into central session/auth code, which is out of this
    // feature's scope.
    ref.listen<AsyncValue<AuthSession>>(authSessionProvider, (previous, next) {
      final previousUserId = previous?.value?.userId;
      final wasSignedIn = previous?.value?.isSignedIn == true;
      final signedOutNow = next.value?.isSignedIn != true;
      if (wasSignedIn && signedOutNow && previousUserId != null) {
        unawaited(
          ref
              .read(notificationPreferencesOutboxRepositoryProvider)
              .clear(previousUserId, deviceId),
        );
      }
    });
    Future.microtask(load);
    return const NotificationPreferencesState();
  }

  String? _currentUserId() => ref.read(authSessionProvider).value?.userId;

  Future<void> load() {
    final active = _activeLoad;
    if (active != null) return active;
    final operation = _load(++_generation);
    _activeLoad = operation;
    return operation.whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
  }

  Future<void> _load(int generation) async {
    state = NotificationPreferencesState(
      phase: NotificationPreferencesPhase.loading,
      baseline: state.baseline,
      draft: state.draft,
    );
    final userId = _currentUserId();
    final outbox = ref.read(notificationPreferencesOutboxRepositoryProvider);
    final pending = userId == null ? null : await outbox.read(userId, deviceId);
    if (!_canApply(generation)) return;

    try {
      final serverValue = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .get(deviceId);
      if (!_canApply(generation)) return;
      await _reconcileOnLoad(userId, outbox, serverValue, pending);
    } on ApiFailure catch (error) {
      if (!_canApply(generation)) return;
      state = NotificationPreferencesState(
        phase: error.kind == ApiFailureKind.unauthorized
            ? NotificationPreferencesPhase.sessionExpired
            : NotificationPreferencesPhase.loadError,
        baseline: state.baseline,
        draft: pending?.pendingDraft ?? state.draft,
        message: error.message,
      );
    }
  }

  /// Reconciles a fresh GET against a locally-outboxed pending edit, per the
  /// "Ao reabrir" contract: an already-applied edit is cleared silently, a
  /// still-valid baseline resumes sync, and an incompatible server change is
  /// surfaced as a recoverable error rather than overwritten blindly.
  Future<void> _reconcileOnLoad(
    String? userId,
    NotificationPreferencesOutboxRepository outbox,
    DeviceNotificationPreferences serverValue,
    NotificationPreferencesOutboxEntry? pending,
  ) async {
    if (pending == null) {
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.ready,
        baseline: serverValue,
        draft: serverValue,
      );
      return;
    }

    if (serverValue.hasSameEditableValues(pending.pendingDraft)) {
      if (userId != null) await outbox.clear(userId, deviceId);
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.ready,
        baseline: serverValue,
        draft: serverValue,
      );
      return;
    }

    if (pending.baselineUpdatedAt == serverValue.updatedAt) {
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.ready,
        baseline: serverValue,
        draft: pending.pendingDraft,
      );
      // Best-effort: try to finish the interrupted sync now. Not required to
      // succeed — the debounce/retry machinery covers failure.
      _scheduleFlush(immediate: true);
      return;
    }

    state = NotificationPreferencesState(
      phase: NotificationPreferencesPhase.saveError,
      baseline: serverValue,
      draft: pending.pendingDraft,
      message:
          'As preferências mudaram no servidor antes de sincronizar suas '
          'alterações. Toque em tentar novamente para reenviar.',
    );
  }

  bool _canApply(int generation) => !_disposed && generation == _generation;

  void edit(
    DeviceNotificationPreferences Function(
      DeviceNotificationPreferences current,
    )
    update,
  ) {
    if (!state.canEdit) return;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.ready,
      draft: update(state.draft!),
      message: null,
    );
    _scheduleFlush();
  }

  Future<void> enableSchedule(bool enabled) async {
    if (!state.canEdit) return;
    if (!enabled) {
      edit(
        (value) => value.copyWith(
          quietSchedule: value.quietSchedule.copyWith(enabled: false),
        ),
      );
      return;
    }

    final existingTimezone = state.draft!.quietSchedule.timezone;
    if (existingTimezone != null) {
      _finishEnablingSchedule(existingTimezone);
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.resolvingTimezone,
      timezoneError: null,
      message: null,
    );
    try {
      final timezone = await ref.read(timezoneLoaderProvider)();
      if (!_canApply(generation)) return;
      _finishEnablingSchedule(timezone);
    } on TimezoneUnavailableException {
      if (!_canApply(generation)) return;
      state = state.copyWith(
        phase: NotificationPreferencesPhase.ready,
        timezoneError:
            'Não foi possível obter o fuso horário. Tente novamente.',
      );
    }
  }

  void _finishEnablingSchedule(String timezone) {
    final currentDraft = state.draft;
    if (currentDraft == null || _disposed) return;
    final current = currentDraft.quietSchedule;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.ready,
      draft: currentDraft.copyWith(
        quietSchedule: current.copyWith(
          enabled: true,
          timezone: timezone,
          days: current.days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : null,
          startTime: current.startTime ?? ClockTime(hour: 22, minute: 0),
          endTime: current.endTime ?? ClockTime(hour: 7, minute: 0),
        ),
      ),
      timezoneError: null,
    );
    _scheduleFlush();
  }

  /// Restores contractual defaults and autosaves them immediately: this is
  /// already a deliberate, confirmed action (behind a confirmation dialog in
  /// the UI), so it skips the debounce used to coalesce raw taps.
  Future<void> resetRemote() async {
    if (!state.canReset) return;
    final baseline = state.baseline!;
    final defaults = baseline.withDefaultEditableValues();
    if (baseline.hasSameEditableValues(defaults)) return;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.ready,
      draft: defaults,
      message: null,
    );
    _scheduleFlush(immediate: true);
  }

  /// Cancels any pending debounce and flushes immediately if there is
  /// something to send. Called by the page on exit as a best-effort attempt
  /// to shrink the window between an edit and the outbox write that
  /// protects it — never required for correctness. Deliberately deferred by
  /// its caller to a microtask (page `dispose()` cannot mutate provider
  /// state synchronously), so by the time this actually runs the provider
  /// may already be fully disposed (e.g. the whole screen/app was torn
  /// down) — checked first so that case is a silent no-op, not a crash.
  void flushPendingNow() {
    if (_disposed) return;
    if (!state.hasChanges) return;
    _scheduleFlush(immediate: true);
  }

  /// Re-attempts a stuck sync: a failed PATCH, an unresolved conflict, or a
  /// failed initial load. A deliberate user action, so — like [resetRemote]
  /// — it bypasses the debounce.
  Future<void> retry() {
    if (state.phase == NotificationPreferencesPhase.loadError) return load();
    if (state.phase == NotificationPreferencesPhase.saveError ||
        state.phase == NotificationPreferencesPhase.conflict) {
      return _flush();
    }
    return Future<void>.value();
  }

  void _scheduleFlush({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      unawaited(_flush());
      return;
    }
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(_flush());
    });
  }

  /// Sends the current delta, if any. At most one PATCH is ever in flight
  /// (concurrent calls fold into the running one); a draft that changed
  /// again mid-flight is picked up by scheduling exactly one more debounced
  /// flush once the response for the current one lands.
  Future<void> _flush() async {
    if (_disposed) return;
    if (_saving) return;
    if (state.phase == NotificationPreferencesPhase.loading ||
        state.phase == NotificationPreferencesPhase.sessionExpired) {
      return;
    }

    final baseline = state.baseline;
    final draft = state.draft;
    if (baseline == null || draft == null) return;
    if (baseline.hasSameEditableValues(draft)) return;

    final validation = draft.quietSchedule.validate();
    if (validation != null) {
      state = state.copyWith(
        phase: NotificationPreferencesPhase.saveError,
        message: validation,
      );
      return;
    }

    final userId = _currentUserId();
    final outbox = ref.read(notificationPreferencesOutboxRepositoryProvider);
    if (userId != null) {
      await outbox.write(
        userId,
        deviceId,
        NotificationPreferencesOutboxEntry(
          pendingDraft: draft,
          baselineUpdatedAt: baseline.updatedAt,
        ),
      );
    }
    if (_disposed) return;

    _saving = true;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.saving,
      message: null,
    );
    try {
      final confirmed = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .patch(deviceId, baseline, draft);
      _saving = false;
      if (_disposed) return;

      // The draft may have changed again while this call was in flight —
      // never let a stale response overwrite a newer choice.
      final latestDraft = state.draft ?? draft;
      final converged = confirmed.hasSameEditableValues(latestDraft);
      if (userId != null) {
        if (converged) {
          await outbox.clear(userId, deviceId);
        } else {
          await outbox.write(
            userId,
            deviceId,
            NotificationPreferencesOutboxEntry(
              pendingDraft: latestDraft,
              baselineUpdatedAt: confirmed.updatedAt,
            ),
          );
        }
      }
      if (_disposed) return;
      state = state.copyWith(
        phase: NotificationPreferencesPhase.ready,
        baseline: confirmed,
        draft: latestDraft,
        message: null,
      );
      if (!converged) _scheduleFlush();
    } on ApiFailure catch (error) {
      _saving = false;
      if (_disposed) return;
      if (error.kind == ApiFailureKind.conflict) {
        await _reconcileConflict(userId, outbox);
        return;
      }
      if (error.kind == ApiFailureKind.unauthorized) {
        state = state.copyWith(
          phase: NotificationPreferencesPhase.sessionExpired,
        );
        if (userId != null) await outbox.clear(userId, deviceId);
        return;
      }
      state = state.copyWith(
        phase: NotificationPreferencesPhase.saveError,
        message: error.message,
      );
    }
  }

  /// At most one reconciliation GET after a 409 — never an automatic re-PATCH
  /// loop. If the server already matches the draft, the conflict resolves
  /// silently; otherwise the app surfaces a recoverable error and waits for
  /// the user to retry rather than guessing how to merge further.
  Future<void> _reconcileConflict(
    String? userId,
    NotificationPreferencesOutboxRepository outbox,
  ) async {
    try {
      final serverValue = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .get(deviceId);
      if (_disposed) return;
      final draft = state.draft ?? serverValue;
      if (serverValue.hasSameEditableValues(draft)) {
        if (userId != null) await outbox.clear(userId, deviceId);
        state = state.copyWith(
          phase: NotificationPreferencesPhase.ready,
          baseline: serverValue,
          draft: serverValue,
          message: null,
        );
        return;
      }
      if (userId != null) {
        await outbox.write(
          userId,
          deviceId,
          NotificationPreferencesOutboxEntry(
            pendingDraft: draft,
            baselineUpdatedAt: serverValue.updatedAt,
          ),
        );
      }
      if (_disposed) return;
      state = state.copyWith(
        phase: NotificationPreferencesPhase.conflict,
        baseline: serverValue,
        message:
            'Estas preferências mudaram em outro lugar. Toque em tentar '
            'novamente para reenviar.',
      );
    } on ApiFailure catch (error) {
      if (_disposed) return;
      if (error.kind == ApiFailureKind.unauthorized) {
        state = state.copyWith(
          phase: NotificationPreferencesPhase.sessionExpired,
        );
        if (userId != null) await outbox.clear(userId, deviceId);
        return;
      }
      state = state.copyWith(
        phase: NotificationPreferencesPhase.conflict,
        message: 'Não foi possível verificar o estado atual. Tente novamente.',
      );
    }
  }
}

const _unset = Object();

final deviceNotificationPreferencesProvider =
    NotifierProvider.family<
      DeviceNotificationPreferencesController,
      NotificationPreferencesState,
      String
    >(DeviceNotificationPreferencesController.new);
