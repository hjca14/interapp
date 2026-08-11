import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// Exposes the live status for one InterBridge device.
///
/// `.family<DeviceStatus, String>` means: one independent provider instance
/// per `deviceId` (the `String`), each wrapping a `Stream<DeviceStatus>` in
/// an `AsyncValue` — so widgets get loading/error/data states for free via
/// `ref.watch(deviceStatusProvider(deviceId)).when(...)`.
///
/// The transport remains hidden behind `DeviceConnectionRepository`, allowing
/// the implementation to change without modifying presentation widgets.
final deviceStatusProvider = StreamProvider.family<DeviceStatus, String>((
  ref,
  deviceId,
) {
  final repository = ref.watch(deviceConnectionRepositoryProvider);
  return repository.watchStatus(deviceId);
});
