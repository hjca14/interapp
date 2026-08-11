import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// Loads and edits one device's [DeviceSettings].
///
/// Unlike `deviceStatusProvider` (a read-only stream from hardware), this is
/// an [AsyncNotifier] because the settings screen also *writes*: every
/// [updateSettings] call persists through `DeviceSettingsRepository` and
/// pushes the new value into `state` so the UI reflects it immediately,
/// without re-reading from storage.
class DeviceSettingsController extends AsyncNotifier<DeviceSettings> {
  DeviceSettingsController(this.deviceId);

  final String deviceId;

  @override
  Future<DeviceSettings> build() {
    return ref.read(deviceSettingsRepositoryProvider).get(deviceId);
  }

  /// Applies [updater] to the current settings, updates `state` right away
  /// (so switches/pickers feel instant — `update` is the protected helper
  /// `AsyncNotifier` already provides for exactly this), then persists.
  Future<void> updateSettings(
    DeviceSettings Function(DeviceSettings current) updater,
  ) async {
    final next = await update((current) => updater(current));
    await ref.read(deviceSettingsRepositoryProvider).save(deviceId, next);
  }

  /// Restores every setting to [DeviceSettings]'s defaults — the "Redefinir
  /// configurações" action. Only clears this app's local preferences; there
  /// is no hardware to reset yet.
  Future<void> reset() => updateSettings((_) => const DeviceSettings());
}

final deviceSettingsProvider =
    AsyncNotifierProvider.family<
      DeviceSettingsController,
      DeviceSettings,
      String
    >(DeviceSettingsController.new);
