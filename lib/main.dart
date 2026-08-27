import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/amplify_bootstrap.dart';
import 'core/config/app_environment.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/push/push_providers.dart';
import 'features/devices/presentation/providers/devices_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = AppConfig.fromEnvironment();
    await AmplifyBootstrap.configure(config);
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(config)],
    );
    await container.read(incomingCallNotificationServiceProvider).initialize();
    if (await FirebaseBootstrap.configure()) {
      await container.read(pushNotificationServiceProvider).initialize();
    }
    runApp(
      UncontrolledProviderScope(container: container, child: const InterApp()),
    );
  } on Object {
    runApp(const _ConfigurationErrorApp());
  }
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Configuração inválida. Informe todos os valores exigidos '
                'via --dart-define e reinicie o aplicativo.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
