import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/app/app.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// App entry point.
///
/// A [ProviderContainer] is created manually (instead of just wrapping
/// [InterApp] in a [ProviderScope]) because [IncomingCallNotificationService]
/// needs an `await` before the first frame is drawn — it asks the OS for
/// notification permission and registers the notification channel. The same
/// container is then handed to the widget tree via [UncontrolledProviderScope]
/// so the rest of the app keeps using `ref.watch`/`ref.read` normally.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  await container.read(incomingCallNotificationServiceProvider).initialize();
  runApp(UncontrolledProviderScope(container: container, child: const InterApp()));
}
