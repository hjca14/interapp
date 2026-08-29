import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/devices/presentation/providers/devices_providers.dart';
import 'app_version_provider.dart';
import 'firebase_messaging_client.dart';
import 'installation_id_store.dart';
import 'push_installation_coordinator.dart';
import 'push_installation_repository.dart';
import 'push_notification_service.dart';

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

/// Built once per process. `main()` still has to call `.initialize()` on it
/// (after `runApp`, not before — see [PushNotificationService.initialize])
/// before its token/permission state is populated.
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    FirebaseMessagingClient(),
    (token) => unawaited(
      ref.read(pushInstallationCoordinatorProvider).then(
        (coordinator) => coordinator.acceptToken(token),
      ),
    ),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

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
