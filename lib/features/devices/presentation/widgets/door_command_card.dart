import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/services/biometric_lock.dart';
import '../../../auth/presentation/providers/biometric_lock_providers.dart';
import '../../../commands/presentation/providers/door_command_provider.dart';
import '../../../sharing/domain/entities/device_access.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/entities/device_settings.dart';
import '../providers/device_settings_provider.dart';

/// Shared OPEN_DOOR surface. Both device details and the incoming-call page
/// use this exact controller/settings/biometric flow.
class DoorCommandCard extends ConsumerStatefulWidget {
  const DoorCommandCard({
    super.key,
    required this.deviceId,
    required this.detail,
  });

  final String deviceId;
  final AsyncValue<ApiDeviceDetail> detail;

  @override
  ConsumerState<DoorCommandCard> createState() => _DoorCommandCardState();
}

class _DoorCommandCardState extends ConsumerState<DoorCommandCard>
    with WidgetsBindingObserver {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _dialogOpen && mounted) {
      _dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(doorCommandProvider(widget.deviceId));
    final settingsAsync = ref.watch(deviceSettingsProvider(widget.deviceId));
    final settings = settingsAsync.value;
    final command = action.state;
    final isOwner = widget.detail.value?.role == DeviceRole.owner;
    final cooldown = command.retryAfter != null;
    final cancelled = command.phase == DoorCommandPhase.cancelled;
    final settingsReady = settings != null && !settingsAsync.hasError;
    final enabled =
        isOwner && settingsReady && !command.busy && !cooldown && !cancelled;
    final subtitle = !isOwner
        ? 'Somente o proprietário pode enviar esta solicitação.'
        : settingsAsync.isLoading
        ? 'Carregando preferências de abertura…'
        : settingsAsync.hasError
        ? 'Não foi possível carregar as preferências de abertura.'
        : switch (command.phase) {
            DoorCommandPhase.preparing => 'Preparando solicitação…',
            DoorCommandPhase.authenticating => 'Confirmando identidade…',
            DoorCommandPhase.sending => 'Enviando solicitação…',
            DoorCommandPhase.waiting => 'Aguardando resposta do dispositivo…',
            DoorCommandPhase.cancelled => 'Solicitação interrompida.',
            _ =>
              command.message ??
                  'A abertura só será confirmada após a resposta do aparelho.',
          };

    return Card(
      child: ListTile(
        leading: command.busy
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.lock_open_outlined),
        title: const Text('Abrir porta'),
        subtitle: Text(subtitle),
        trailing: command.canRetryCreate
            ? FilledButton(
                onPressed: !enabled ? null : action.retryCreateAfterTimeout,
                child: const Text('Tentar novamente'),
              )
            : FilledButton(
                onPressed: enabled
                    ? () => _prepareAndStart(action, settings)
                    : null,
                child: const Text('Abrir'),
              ),
      ),
    );
  }

  Future<void> _prepareAndStart(
    DoorCommandActionController action,
    DeviceSettings settings,
  ) async {
    final preparation = action.beginPreparation();
    if (preparation == null) return;
    if (settings.confirmBeforeOpeningDoor) {
      _dialogOpen = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Abrir porta?'),
          content: const Text(
            'O InterBridge enviará uma solicitação ao dispositivo. '
            'A abertura só será confirmada após a resposta do aparelho.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar solicitação'),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (confirmed != true || !action.isPreparationCurrent(preparation)) {
        action.finishPreparation(preparation);
        return;
      }
    }
    if (settings.requireDeviceAuthenticationToOpenDoor) {
      if (!action.beginAuthentication(preparation)) return;
      final result = await _authenticateDevice();
      if (!action.isPreparationCurrent(preparation)) return;
      if (result != BiometricAuthenticationResult.success) {
        action.finishPreparation(preparation);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_doorAuthenticationMessage(result))),
          );
        }
        return;
      }
    }
    if (action.isPreparationCurrent(preparation)) {
      action.finishPreparation(preparation);
      await action.start();
    }
  }

  Future<BiometricAuthenticationResult> _authenticateDevice() async {
    try {
      final authenticator = ref.read(doorDeviceAuthenticatorProvider);
      return switch (await authenticator.availability()) {
        BiometricAvailability.available => await authenticator.authenticate(),
        BiometricAvailability.notEnrolled =>
          BiometricAuthenticationResult.notEnrolled,
        BiometricAvailability.unsupported =>
          BiometricAuthenticationResult.unsupported,
      };
    } on Object {
      return BiometricAuthenticationResult.failed;
    }
  }

  String _doorAuthenticationMessage(BiometricAuthenticationResult result) =>
      switch (result) {
        BiometricAuthenticationResult.canceled => 'Autenticação cancelada.',
        BiometricAuthenticationResult.notEnrolled ||
        BiometricAuthenticationResult.unsupported =>
          'Autenticação segura do aparelho indisponível.',
        BiometricAuthenticationResult.temporarilyLocked =>
          'Autenticação temporariamente bloqueada.',
        BiometricAuthenticationResult.failed =>
          'Não foi possível confirmar sua identidade.',
        BiometricAuthenticationResult.success => '',
      };
}
