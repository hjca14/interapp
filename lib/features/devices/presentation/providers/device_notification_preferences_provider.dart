import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

enum NotificationPreferencesPhase {
  loading,
  ready,
  saving,
  saved,
  error,
  conflict,
  sessionExpired,
}

class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.phase = NotificationPreferencesPhase.loading,
    this.baseline,
    this.draft,
    this.message,
  });
  final NotificationPreferencesPhase phase;
  final DeviceNotificationPreferences? baseline;
  final DeviceNotificationPreferences? draft;
  final String? message;
  bool get hasChanges => baseline != null && draft != baseline;
  bool get canSave =>
      hasChanges && phase != NotificationPreferencesPhase.saving;
  NotificationPreferencesState copyWith({
    NotificationPreferencesPhase? phase,
    DeviceNotificationPreferences? baseline,
    DeviceNotificationPreferences? draft,
    String? message,
  }) => NotificationPreferencesState(
    phase: phase ?? this.phase,
    baseline: baseline ?? this.baseline,
    draft: draft ?? this.draft,
    message: message,
  );
}

typedef TimezoneLoader = Future<String> Function();
final timezoneLoaderProvider = Provider<TimezoneLoader>((_) => () async {
  const channel = MethodChannel('interapp/device_timezone');
  final identifier = await channel.invokeMethod<String>('getIdentifier');
  if (identifier == null || identifier.isEmpty) {
    throw StateError('timezone unavailable');
  }
  return identifier;
});

class DeviceNotificationPreferencesController
    extends Notifier<NotificationPreferencesState> {
  DeviceNotificationPreferencesController(this.deviceId);
  final String deviceId;

  @override
  NotificationPreferencesState build() {
    Future.microtask(load);
    return const NotificationPreferencesState();
  }

  Future<void> load() async {
    state = NotificationPreferencesState(
      phase: NotificationPreferencesPhase.loading,
      baseline: state.baseline,
      draft: state.draft,
    );
    try {
      final value = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .get(deviceId);
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.ready,
        baseline: value,
        draft: value,
      );
    } on ApiFailure catch (error) {
      state = NotificationPreferencesState(
        phase: error.kind == ApiFailureKind.unauthorized
            ? NotificationPreferencesPhase.sessionExpired
            : NotificationPreferencesPhase.error,
        baseline: state.baseline,
        draft: state.draft,
        message: error.message,
      );
    }
  }

  void edit(DeviceNotificationPreferences Function(DeviceNotificationPreferences) update) {
    if (state.draft == null || state.phase == NotificationPreferencesPhase.saving) return;
    state = state.copyWith(phase: NotificationPreferencesPhase.ready, draft: update(state.draft!));
  }

  Future<void> enableSchedule(bool enabled) async {
    if (!enabled) {
      edit((value) => value.copyWith(
        quietSchedule: value.quietSchedule.copyWith(enabled: false),
      ));
      return;
    }
    final current = state.draft?.quietSchedule;
    if (current == null) return;
    try {
      final timezone = current.timezone ?? await ref.read(timezoneLoaderProvider)();
      edit((value) => value.copyWith(
        quietSchedule: current.copyWith(
          enabled: true,
          timezone: timezone,
          days: current.days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : null,
          startTime: current.startTime ?? const ClockTime(22, 0),
          endTime: current.endTime ?? const ClockTime(7, 0),
        ),
      ));
    } on Object {
      state = state.copyWith(
        phase: NotificationPreferencesPhase.error,
        message: 'Não foi possível obter o fuso horário. Tente novamente.',
      );
    }
  }

  void discard() {
    if (state.baseline == null) return;
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
    final validation = draft.quietSchedule.validate();
    if (validation != null) {
      state = state.copyWith(
        phase: NotificationPreferencesPhase.error,
        message: validation,
      );
      return;
    }
    state = state.copyWith(phase: NotificationPreferencesPhase.saving);
    try {
      final confirmed = await ref
          .read(deviceNotificationPreferencesRepositoryProvider)
          .patch(deviceId, baseline, draft);
      state = NotificationPreferencesState(
        phase: NotificationPreferencesPhase.saved,
        baseline: confirmed,
        draft: confirmed,
      );
    } on ApiFailure catch (error) {
      state = state.copyWith(
        phase: switch (error.kind) {
          ApiFailureKind.conflict => NotificationPreferencesPhase.conflict,
          ApiFailureKind.unauthorized => NotificationPreferencesPhase.sessionExpired,
          _ => NotificationPreferencesPhase.error,
        },
        message: error.message,
      );
    }
  }

  Future<void> resetRemote() async {
    if (state.draft == null) return;
    edit((_) => const DeviceNotificationPreferences());
    await save();
  }
}

final deviceNotificationPreferencesProvider = NotifierProvider.family<
    DeviceNotificationPreferencesController,
    NotificationPreferencesState,
    String>(DeviceNotificationPreferencesController.new);
