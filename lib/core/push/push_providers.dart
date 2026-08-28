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
    tokenSink: (token) => unawaited(
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

/// Starts the auth/token rendezvous after the first frame. Failures are
/// deliberately isolated from normal application startup.
Future<void> initializePushInstallationIntegration(
  ProviderContainer container,
) async {
  try {
    final coordinator = await container.read(
      pushInstallationCoordinatorProvider,
    );
    container.listen(authSessionProvider, (_, next) {
      next.whenData(
        (session) => coordinator.setAuthenticated(session.isSignedIn),
      );
    }, fireImmediately: true);
  } on Object {
    // Push registration is best effort and must not affect the app shell.
  }
}
