import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../devices/presentation/providers/devices_providers.dart';
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
                } on BiometricActivationException catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(biometricResultMessage(error.result)),
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
            const Divider(),
            const _FullScreenCallAccessSection(),
          ],
        ),
      ),
    );
  }
}

/// Voluntary, informational only: never shown as a banner/prompt elsewhere,
/// never triggered automatically on boot/login/push — the user must open
/// this screen and tap the button themselves. See
/// `IncomingCallNotificationService.requestFullScreenIntentAccess`.
///
/// The status shown here is re-checked, never just read from a stale cache:
/// [fullScreenIntentAccessProvider] is `autoDispose`, so leaving this screen
/// and coming back always re-queries the OS, and a [WidgetsBindingObserver]
/// also re-queries on every app resume — covering the common flow of
/// backgrounding the app to toggle the permission in Android Settings and
/// coming straight back without ever leaving this screen.
class _FullScreenCallAccessSection extends ConsumerStatefulWidget {
  const _FullScreenCallAccessSection();

  @override
  ConsumerState<_FullScreenCallAccessSection> createState() =>
      _FullScreenCallAccessSectionState();
}

class _FullScreenCallAccessSectionState
    extends ConsumerState<_FullScreenCallAccessSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(fullScreenIntentAccessProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(fullScreenIntentAccessProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chamada em tela cheia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'No Android 14 ou superior, o sistema pode exigir uma permissão '
            'especial para abrir a tela de chamada sobre a tela bloqueada. '
            'Sem ela, você ainda recebe um aviso funcional na tela, só que '
            'sem abrir automaticamente.',
          ),
          const SizedBox(height: 12),
          switch (status) {
            AsyncData(:final value) when value => const _AccessRow(
              icon: Icons.check_circle_outline,
              label: 'Ativado',
            ),
            AsyncData() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AccessRow(
                  icon: Icons.info_outline,
                  label: 'Não ativado',
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _requestAccess(ref),
                  child: const Text('Abrir configuração do Android'),
                ),
              ],
            ),
            AsyncError() => const _AccessRow(
              icon: Icons.info_outline,
              label: 'Não foi possível verificar.',
            ),
            _ => const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _requestAccess(WidgetRef ref) async {
    await ref
        .read(incomingCallNotificationServiceProvider)
        .requestFullScreenIntentAccess();
    ref.invalidate(fullScreenIntentAccessProvider);
  }
}

class _AccessRow extends StatelessWidget {
  const _AccessRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(label)],
  );
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
