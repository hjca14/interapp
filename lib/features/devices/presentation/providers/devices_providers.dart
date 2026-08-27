import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/config/app_environment.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/devices/data/repositories/http_device_repository.dart';
import 'package:interapp/features/devices/data/repositories/http_device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_backend_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/repositories/device_backend_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

// Central place where every repository/service used by the `devices` feature
// (and a couple of cross-feature ones) is wired up for Riverpod. Screens read
// these instead of constructing repositories themselves, so swapping an
// implementation later (e.g. local -> Supabase) only touches this file.

final devicesRepositoryProvider = Provider<LocalDevicesRepository>(
  (_) => LocalDevicesRepository(),
);

final appConfigProvider = Provider<AppConfig>(
  (_) => throw StateError('AppConfig não inicializado'),
);

final apiClientProvider = Provider<InterBridgeApiClient>((ref) {
  return InterBridgeApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    auth: ref.watch(authRepositoryProvider),
  );
});

final httpDeviceRepositoryProvider = Provider<HttpDeviceRepository>((ref) {
  return HttpDeviceRepository(ref.watch(apiClientProvider));
});

/// Typed as the abstract [DeviceRepository] so the device list, details and
/// rename screens depend on the contract, not on [HttpDeviceRepository]
/// directly. It reads the same instance as [httpDeviceRepositoryProvider]
/// (list/detail are already real and deployed). The rename contract is
/// confirmed, while its backend implementation is not yet deployed to AWS.
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return ref.watch(httpDeviceRepositoryProvider);
});

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

final deviceNotificationPreferencesRepositoryProvider =
    Provider<DeviceNotificationPreferencesRepository>((ref) {
      return HttpDeviceNotificationPreferencesRepository(
        ref.watch(apiClientProvider),
      );
    });

final profileRepositoryProvider = Provider<LocalProfileRepository>(
  (_) => LocalProfileRepository(),
);

/// The AWS application backend's API, abstracted — see
/// `DeviceBackendRepository`'s doc comment. Not the same seam as
/// [deviceConnectionRepositoryProvider]: this represents "what the backend
/// exposes", not "how the app talks to a device". A future
/// `CloudDeviceConnectionRepository` would read from this provider and
/// implement [DeviceConnectionRepository] on top of it.
final deviceBackendRepositoryProvider = Provider<DeviceBackendRepository>(
  (_) => LocalDeviceBackendRepository(),
);

/// Note this only builds the service — `main()` still has to call
/// `.initialize()` on it before it's usable.
final incomingCallNotificationServiceProvider =
    Provider<IncomingCallNotificationService>(
      (_) => IncomingCallNotificationService(FlutterLocalNotificationsPlugin()),
    );
