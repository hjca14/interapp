import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/config/app_environment.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/core/push/notification_tap_router.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_lock_screen_channel.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/devices/data/repositories/http_device_repository.dart';
import 'package:interapp/features/devices/data/repositories/http_device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_backend_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_device_settings_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_notification_preferences_outbox_repository.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/repositories/device_backend_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/repositories/notification_preferences_outbox_repository.dart';
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

/// Local sync-intent outbox for notification-preferences autosave — a cache
/// of "what the user last chose but the server hasn't confirmed yet", never
/// a source of truth. See [LocalNotificationPreferencesOutboxRepository].
final notificationPreferencesOutboxRepositoryProvider =
    Provider<NotificationPreferencesOutboxRepository>(
      (_) => LocalNotificationPreferencesOutboxRepository(),
    );

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
    Provider<IncomingCallNotificationService>((ref) {
      // Declared before construction so onInvalidCallTap below can call back
      // into this same instance to cancel-by-id without a self-referential
      // `ref.read(incomingCallNotificationServiceProvider)`, which would
      // make this provider's own type inference cyclic. Safe: the closure
      // only reads [service] once actually invoked, always after this
      // provider has finished building and returned it.
      late final IncomingCallNotificationService service;
      service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
        // Both RING_ONLY and NOTIFICATION_ONLY taps carry a RingCallIntent
        // payload (see IncomingCallNotificationService.present's doc — both
        // represent the same live call session) and reach the same
        // navigation coordinator/IncomingCallPage. See `routeNotificationTap`.
        onRingNotificationTap: (payload, notificationId) =>
            routeNotificationTap(
              payload,
              onCallTap: ref
                  .read(ringCallNavigationCoordinatorProvider)
                  .acceptSerialized,
              // The payload had a call notification's shape but failed to
              // restore (expired past the ring-timeout, malformed, foreign
              // version) — recover safely without opening IncomingCallPage:
              // cancel exactly the tapped notification by its own OS id (never
              // derived from the untrusted payload), and undo any lock-screen
              // bypass in case MainActivity had already granted one from the
              // launching Intent alone. Never touches any other
              // call/notification, and never stops the ringtone for a call that
              // is actually still valid — this is a distinct branch from
              // onCallTap above.
              onInvalidCallTap: notificationId == null
                  ? null
                  : () {
                      unawaited(service.cancelNotificationById(notificationId));
                      unawaited(endRingCallLockScreenPresentation());
                    },
              onDiagnostic: (diagnostic) {
                if (kDebugMode) {
                  debugPrint(diagnostic.toLogLine());
                }
              },
            ),
        // A RING_ENDED/local ring-timeout cancels the notification here,
        // and must also close an already-open IncomingCallPage/abort a
        // pending one — see IncomingCallNotificationService.endCall's doc.
        onCallEnded: (callId) =>
            ref.read(ringCallNavigationCoordinatorProvider).endCall(callId),
        // This instance is the one the *foreground* listener presents
        // through (see push_providers.dart's _handleForegroundRingPush) —
        // reaching this callback means InterBridge is already in
        // foreground, so open IncomingCallPage directly instead of waiting
        // on a tap/Android's own full-screen-intent decision. See
        // IncomingCallNotificationService.onCallPresented's doc.
        onCallPresented: (event) => ref
            .read(ringCallNavigationCoordinatorProvider)
            .acceptSerialized(RingCallIntent.fromEvent(event).serialize()),
      );
      return service;
    });

final ringCallNavigationCoordinatorProvider =
    Provider<RingCallNavigationCoordinator>((ref) {
      final coordinator = RingCallNavigationCoordinator((deviceId) async {
        await ref.read(deviceRepositoryProvider).getDeviceDetails(deviceId);
        return true;
      });
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

/// Read-only status for `SecuritySettingsPage`. `ref.invalidate` this after
/// [requestFullScreenIntentAccess] resolves to reflect a just-granted (or
/// still-denied) result, and also on every app resume and re-entry to the
/// screen — see `_FullScreenCallAccessSectionState`. `autoDispose` so that
/// re-entry actually re-queries the OS instead of showing a value cached
/// from a previous visit: once `SecuritySettingsPage` is popped and nothing
/// else watches this, its cached result is dropped.
final fullScreenIntentAccessProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref
      .read(incomingCallNotificationServiceProvider)
      .hasFullScreenIntentAccess(),
);
