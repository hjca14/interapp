import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/app/app.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  await container.read(incomingCallNotificationServiceProvider).initialize();
  runApp(UncontrolledProviderScope(container: container, child: const InterApp()));
}
