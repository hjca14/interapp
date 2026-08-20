import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/biometric_lock_providers.dart';

/// Settings UI for the optional local biometric lock.
class SecuritySettingsPage extends ConsumerWidget {
  const SecuritySettingsPage({super.key});

  static const _timeouts = <Duration>[
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(biometricLockSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Segurança')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não foi possível carregar as preferências.'),
        ),
        data: (value) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Bloqueio biométrico'),
              subtitle: const Text(
                'Protege localmente uma sessão Cognito ainda válida. '
                'Não substitui o login e não armazena sua senha.',
              ),
              value: value.enabled,
              onChanged: (enabled) async {
                try {
                  await ref
                      .read(biometricLockSettingsProvider.notifier)
                      .setEnabled(enabled);
                } on BiometricUnavailableException {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Biometria indisponível ou não cadastrada neste aparelho.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              enabled: value.enabled,
              title: const Text('Bloquear depois de'),
              trailing: DropdownButton<Duration>(
                value: value.backgroundTimeout,
                items: _timeouts
                    .map(
                      (timeout) => DropdownMenuItem(
                        value: timeout,
                        child: Text(_timeoutLabel(timeout)),
                      ),
                    )
                    .toList(),
                onChanged: value.enabled
                    ? (timeout) {
                        if (timeout != null) {
                          ref
                              .read(biometricLockSettingsProvider.notifier)
                              .setTimeout(timeout);
                        }
                      }
                    : null,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Se a sessão expirar ou for revogada, será necessário entrar '
                'normalmente com e-mail e senha.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeoutLabel(Duration timeout) {
  if (timeout == Duration.zero) {
    return 'Imediatamente';
  }
  if (timeout.inSeconds == 30) {
    return '30 segundos';
  }
  if (timeout.inMinutes == 1) {
    return '1 minuto';
  }
  return '${timeout.inMinutes} minutos';
}
