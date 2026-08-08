import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

// Central place where every repository/service used by the `devices` feature
// (and a couple of cross-feature ones) is wired up for Riverpod. Screens read
// these instead of constructing repositories themselves, so swapping an
// implementation later (e.g. local -> Supabase) only touches this file.

final devicesRepositoryProvider = Provider<LocalDevicesRepository>(
  (_) => LocalDevicesRepository(),
);

/// Typed as the abstract [DeviceConnectionRepository], not the local class —
/// this is the seam a future Bluetooth/Wi-Fi/MQTT implementation plugs into
/// without any presentation code changing.
final deviceConnectionRepositoryProvider = Provider<DeviceConnectionRepository>(
  (_) => LocalDeviceConnectionRepository(),
);

final favoritesRepositoryProvider = Provider<LocalFavoritesRepository>(
  (_) => LocalFavoritesRepository(),
);

/// Same seam as [deviceConnectionRepositoryProvider]: typed as the abstract
/// contract so a future remote implementation can replace
/// [LocalDeviceSettingsRepository] without touching `DeviceSettingsPage`.
final deviceSettingsRepositoryProvider = Provider<DeviceSettingsRepository>(
  (_) => LocalDeviceSettingsRepository(),
);

final profileRepositoryProvider = Provider<LocalProfileRepository>(
  (_) => LocalProfileRepository(),
);

/// Note this only builds the service — `main()` still has to call
/// `.initialize()` on it before it's usable.
final incomingCallNotificationServiceProvider = Provider<IncomingCallNotificationService>(
  (_) => IncomingCallNotificationService(FlutterLocalNotificationsPlugin()),
);
