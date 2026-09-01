import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/devices/presentation/providers/devices_providers.dart';
import 'app_version_provider.dart';
import 'firebase_messaging_client.dart';
import 'installation_id_store.dart';
import 'push_installation_coordinator.dart';
import 'push_installation_repository.dart';
import 'push_message.dart';
import 'push_notification_service.dart';
import 'ring_call_lock_screen_channel.dart';
import 'ring_call_navigation.dart';
import 'ring_detected_presenter.dart';
import 'ring_event_deduplicator.dart';

final pushInstallationCoordinatorProvider =
    Provider<Future<PushInstallationCoordinator>>((ref) async {
      final preferences = await SharedPreferences.getInstance();
      return PushInstallationCoordinator(
        installationIds: SharedPreferencesInstallationIdStore(
          SharedPreferencesStringStore(preferences),
        ),
        appVersions: PackageInfoAppVersionProvider(),
        repository: HttpPushInstallationRepository(ref.read(apiClientProvider)),
      );
    });

/// Built once per process, backed by the same [SharedPreferences] instance
/// so a `RING_DETECTED` `event_id` seen by the foreground listener is also
/// visible to the separate background isolate handler, and vice versa —
/// see `ring_event_deduplicator.dart` for what that guarantees (and does
/// not).
final ringEventDeduplicatorProvider = Provider<Future<RingEventDeduplicator>>((
  ref,
) async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesRingEventDeduplicator(
    SharedPreferencesStringStore(preferences),
  );
});

/// Built once per process. `main()` still has to call `.initialize()` on it
/// (after `runApp`, not before — see [PushNotificationService.initialize])
/// before its token/permission state is populated.
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    FirebaseMessagingClient(),
    (token) => unawaited(
      ref
          .read(pushInstallationCoordinatorProvider)
          .then((coordinator) => coordinator.acceptToken(token)),
    ),
    onForegroundMessage: (message) =>
        unawaited(_handleForegroundRingPush(ref, message)),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

/// Reuses the same [incomingCallNotificationServiceProvider] instance (and
/// its already-registered channels/plugin init from `main()`) as the
/// presenter — this is the foreground counterpart of the background
/// isolate's own `presentRingDetectedPush` call in
/// `firebaseMessagingBackgroundHandler`. Never throws:
/// `presentRingDetectedPush` swallows its own failures.
Future<void> _handleForegroundRingPush(Ref ref, PushMessage message) async {
  final deduplicator = await ref.read(ringEventDeduplicatorProvider);
  final presenter = ref.read(incomingCallNotificationServiceProvider);
  await presentRingDetectedPush(
    data: message.data,
    presenter: presenter,
    deduplicator: deduplicator,
    path: 'foreground',
    onDiagnostic: (diagnostic) {
      if (kDebugMode) {
        debugPrint(diagnostic.toLogLine());
      }
    },
  );
}

/// Owns exactly one auth subscription. Riverpod closes it with the provider,
/// so repeated reads are idempotent and disposed test/app containers cannot
/// keep reacting to session changes.
final pushInstallationIntegrationProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final coordinator = ref.watch(pushInstallationCoordinatorProvider);

  Future<void> updateAuthentication(bool isSignedIn) async {
    try {
      final value = await coordinator;
      if (!disposed) {
        value.setAuthenticated(isSignedIn);
      }
    } on Object {
      // Push registration remains isolated from authentication and app use.
    }
  }

  ref.listen(authSessionProvider, (_, next) {
    next.whenData((session) {
      unawaited(updateAuthentication(session.isSignedIn));
    });
  }, fireImmediately: true);
});

/// Delivers authentication readiness to the pending local-notification
/// intent. Authorization of the referenced device is still performed by
/// [RingCallNavigationCoordinator] before the router is notified.
final ringCallNavigationIntegrationProvider = Provider<void>((ref) {
  final coordinator = ref.watch(ringCallNavigationCoordinatorProvider);
  ref.listen(authSessionProvider, (_, next) {
    next.whenData(
      (session) => coordinator.setAuthenticated(session.isSignedIn),
    );
  }, fireImmediately: true);
});

/// Reacts to a call ending no matter which path did it — answered,
/// dismissed, a remote `RING_ENDED`, or the coordinator's own internal
/// ring-timeout — by diffing
/// [RingCallNavigationCoordinator.trackedCallId] across
/// [ChangeNotifier.notifyListeners] calls, since that is the one signal
/// common to every path, including the timeout, which has no external
/// notification of its own:
///
/// - undoes `MainActivity`'s lock-screen bypass, returning to the system
///   keyguard if it is still actually engaged, once nothing is
///   pending/active any more — not only once a call was fully active:
///   `MainActivity` grants the bypass from the launching Intent's payload
///   alone, before Dart-side authorization is known, so a call dropped
///   while still pending (e.g. an unauthorized device) must revert it just
///   as much as one that was answered/dismissed, or the app would be left
///   showing ordinary content over a still-locked keyguard. See
///   [endRingCallLockScreenPresentation]'s doc for why this call is safe
///   even for a call that was never shown over a locked keyguard;
/// - cancels the ended call's notification (and with it, the insistent
///   ringtone). Redundant with, and harmless alongside, the paths that
///   already do this themselves at their own call site
///   (`IncomingCallNotificationService.endCall` for a remote `RING_ENDED`,
///   `IncomingCallPage._dismiss`/`_answer` for the user) — this is what
///   covers the internal ring-timeout, which cancels nothing on its own
///   (`RingCallNavigationCoordinator` never depends on
///   `IncomingCallNotificationService`, avoiding a circular provider
///   dependency between the two).
final ringCallEndIntegrationProvider = Provider<void>((ref) {
  final coordinator = ref.watch(ringCallNavigationCoordinatorProvider);
  var lastCallId = coordinator.trackedCallId;
  void listener() {
    final currentCallId = coordinator.trackedCallId;
    final endedCallId = lastCallId;
    final wasTrackingSomething = endedCallId != null;
    if (endedCallId != null && endedCallId != currentCallId) {
      unawaited(
        ref
            .read(incomingCallNotificationServiceProvider)
            .cancelRing(endedCallId),
      );
    }
    if (wasTrackingSomething && currentCallId == null) {
      unawaited(endRingCallLockScreenPresentation());
    }
    lastCallId = currentCallId;
  }

  coordinator.addListener(listener);
  ref.onDispose(() => coordinator.removeListener(listener));
});
