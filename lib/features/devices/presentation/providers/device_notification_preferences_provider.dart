import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

enum NotificationPreferencesPhase {
  loading,
  ready,
  resolvingTimezone,
  saving,
  saved,
  loadError,
  saveError,
  conflict,
  sessionExpired,
}

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

  bool get canEdit =>
      draft != null &&
      switch (phase) {
        NotificationPreferencesPhase.ready ||
        NotificationPreferencesPhase.saved ||
        NotificationPreferencesPhase.saveError => true,
        _ => false,
      };

  bool get canSave => canEdit && hasChanges;
  bool get canDiscard =>
      hasChanges &&
      phase != NotificationPreferencesPhase.loading &&
      phase != NotificationPreferencesPhase.saving &&
      phase != NotificationPreferencesPhase.resolvingTimezone;
  bool get canReset => canEdit && baseline != null;

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
  Future<void>? _activeLoad;
  int _generation = 0;
  bool _disposed = false;

  @override
  NotificationPreferencesState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    Future.microtask(load);
    return const NotificationPreferencesState();
  }

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
    try {
      final value = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .get(deviceId);
      if (!_canApply(generation)) return;
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.ready,
        baseline: value,
        draft: value,
      );
    } on ApiFailure catch (error) {
      if (!_canApply(generation)) return;
      state = NotificationPreferencesState(
        phase: error.kind == ApiFailureKind.unauthorized
            ? NotificationPreferencesPhase.sessionExpired
            : NotificationPreferencesPhase.loadError,
        baseline: state.baseline,
        draft: state.draft,
        message: error.message,
      );
    }
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
          startTime:
              current.startTime ?? ClockTime(hour: 22, minute: 0),
          endTime: current.endTime ?? ClockTime(hour: 7, minute: 0),
        ),
      ),
      timezoneError: null,
    );
  }

  void discard() {
    if (!state.canDiscard) return;
    state = NotificationPreferencesState(
      phase: NotificationPreferencesPhase.ready,
      baseline: state.baseline,
      draft: state.baseline,
    );
  }

  Future<void> save() async {
    if (!state.canSave) return;
    final baseline = state.baseline!;
    final draft = state.draft!;
    if (baseline.hasSameEditableValues(draft)) return;

    final validation = draft.quietSchedule.validate();
    if (validation != null) {
      state = state.copyWith(
        phase: NotificationPreferencesPhase.saveError,
        message: validation,
      );
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(
      phase: NotificationPreferencesPhase.saving,
      message: null,
      timezoneError: null,
    );
    try {
      final confirmed = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .patch(deviceId, baseline, draft);
      if (!_canApply(generation)) return;
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.saved,
        baseline: confirmed,
        draft: confirmed,
        message: 'Preferências salvas.',
      );
    } on ApiFailure catch (error) {
      if (!_canApply(generation)) return;
      state = state.copyWith(
        phase: switch (error.kind) {
          ApiFailureKind.conflict => NotificationPreferencesPhase.conflict,
          ApiFailureKind.unauthorized =>
            NotificationPreferencesPhase.sessionExpired,
          _ => NotificationPreferencesPhase.saveError,
        },
        message: error.kind == ApiFailureKind.conflict
            ? 'Estas preferências mudaram em outro lugar.'
            : error.message,
      );
    }
  }

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
    await save();
  }
}

const _unset = Object();

final deviceNotificationPreferencesProvider = NotifierProvider.family<
  DeviceNotificationPreferencesController,
  NotificationPreferencesState,
  String
>(DeviceNotificationPreferencesController.new);
