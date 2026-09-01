import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/ring_call_intent.dart';
import '../../../sharing/domain/entities/device_access.dart';
import '../../domain/entities/api_device.dart';
import '../providers/api_devices_provider.dart';
import '../providers/devices_providers.dart';
import '../providers/device_settings_provider.dart';
import '../widgets/door_command_card.dart';

/// Honest in-app destination for a validated local RING_DETECTED notification.
/// It does not create an audio session or send answer/reject commands.
class IncomingCallPage extends ConsumerWidget {
  const IncomingCallPage({
    super.key,
    required this.intent,
    required this.onDismiss,
  });

  final RingCallIntent intent;
  final VoidCallback onDismiss;

  /// There is no real audio session to "answer" into yet, so this stays an
  /// honest placeholder instead of pretending a call connected: it shows the
  /// message, then ends the call exactly like [_dismiss] does (ringtone,
  /// notification, coordinator state, lock-screen bypass, previous
  /// route/keyguard). Leaving the call open indefinitely after Atender would
  /// remove the 60s/`RING_ENDED` safety net for the one scenario it exists
  /// for — the user believing something is still happening when nothing is.
  ///
  /// `ScaffoldMessenger.of(context)` resolves to `MaterialApp`'s own
  /// ancestor messenger (above `RingCallOverlay`/the routed content), so the
  /// SnackBar keeps showing on whatever becomes visible once this page
  /// unmounts — reading it before `_endCall` is what makes that safe.
  void _answer(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Áudio ainda não disponível nesta versão.')),
    );
    _endCall(ref);
  }

  void _dismiss(WidgetRef ref) => _endCall(ref);

  void _endCall(WidgetRef ref) {
    unawaited(
      ref
          .read(incomingCallNotificationServiceProvider)
          .cancelRing(intent.callId),
    );
    ref.read(ringCallNavigationCoordinatorProvider).endCall(intent.callId);
    onDismiss();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(apiDeviceDetailProvider(intent.deviceId));
    final knownName = knownDeviceName(
      ref.watch(apiDevicesProvider),
      intent.deviceId,
    );
    final name = resolveKnownDeviceName(
      detailLoaded: detail.hasValue,
      confirmedDisplayName: detail.value?.displayName,
      knownName: knownName,
    );
    final canOpenDoor = detail.value?.role == DeviceRole.owner;
    final doorOpeningEnabled =
        ref
            .watch(deviceSettingsProvider(intent.deviceId))
            .value
            ?.doorOpeningEnabled ==
        true;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Chamada recebida')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.speaker_phone,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Interfone tocando',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                name ?? 'Carregando dispositivo…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (detail.hasError) ...[
                const SizedBox(height: 8),
                const Text(
                  'Não foi possível carregar o nome do dispositivo.',
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () => _answer(context, ref),
                icon: const Icon(Icons.call),
                label: const Text('Atender'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _dismiss(ref),
                icon: const Icon(Icons.call_end),
                label: const Text('Dispensar'),
              ),
              if (canOpenDoor && doorOpeningEnabled) ...[
                const SizedBox(height: 24),
                DoorCommandCard(deviceId: intent.deviceId, detail: detail),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
