import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// Exposes the live status for one InterBridge device.
///
/// The transport remains hidden behind [DeviceConnectionRepository], allowing
/// the implementation to change without modifying presentation widgets.
final deviceStatusProvider = StreamProvider.family<DeviceStatus, String>(
  (ref, deviceId) {
    final repository = ref.watch(deviceConnectionRepositoryProvider);
    return repository.watchStatus(deviceId);
  },
);
