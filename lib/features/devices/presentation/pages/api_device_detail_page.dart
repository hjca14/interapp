import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialer/presentation/controllers/dialer_controller.dart';
import '../../../dialer/presentation/pages/dialer_page.dart';
import '../../../favorites/presentation/pages/favorites_page.dart';
import '../../../commands/presentation/providers/door_command_provider.dart';
import '../../../sharing/domain/entities/device_access.dart';
import '../../domain/entities/api_device.dart';
import 'device_settings_page.dart';
import '../providers/api_devices_provider.dart';
import '../providers/devices_providers.dart';

/// The single device experience: backend-authoritative summary/status plus
/// local-only dialer, favorites and preferences scoped to the real device id.
class ApiDeviceDetailPage extends ConsumerStatefulWidget {
  const ApiDeviceDetailPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<ApiDeviceDetailPage> createState() =>
      _ApiDeviceDetailPageState();
}

class _ApiDeviceDetailPageState extends ConsumerState<ApiDeviceDetailPage> {
  final _dialerController = DialerController();
  int _selectedIndex = 0;

  void _dialFavorite(String number) {
    _dialerController.setNumber(number);
    setState(() => _selectedIndex = 1);
  }

  @override
  void dispose() {
    _dialerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(apiDeviceDetailProvider(widget.deviceId));
    final title = detail.value?.displayName ?? 'InterBridge';
    final pages = [
      _DeviceOverview(deviceId: widget.deviceId),
      DialerPage(controller: _dialerController),
      FavoritesPage(
        repository: ref.watch(favoritesRepositoryProvider),
        deviceId: widget.deviceId,
        onDialFavorite: _dialFavorite,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeviceSettingsPage(
                  deviceId: widget.deviceId,
                  deviceName: title,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Resumo',
          ),
          NavigationDestination(
            icon: Icon(Icons.speaker_phone),
            selectedIcon: Icon(Icons.dialpad),
            label: 'Discar',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Favoritos',
          ),
        ],
      ),
    );
  }
}

class _DeviceOverview extends ConsumerWidget {
  const _DeviceOverview({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(apiDeviceDetailProvider(deviceId));
    final status = ref.watch(apiDeviceStatusProvider(deviceId));
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.refresh(apiDeviceDetailProvider(deviceId).future),
          ref.refresh(apiDeviceStatusProvider(deviceId).future),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DetailCard(deviceId: deviceId, detail: detail),
          const SizedBox(height: 12),
          _StatusCard(deviceId: deviceId, status: status),
          const SizedBox(height: 12),
          _DoorCommandCard(deviceId: deviceId, detail: detail),
          const SizedBox(height: 24),
          Text(
            'Eventos recentes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('Histórico ainda indisponível'),
              subtitle: Text(
                'Eventos reais aparecerão aqui em uma fase futura.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoorCommandCard extends ConsumerWidget {
  const _DoorCommandCard({required this.deviceId, required this.detail});

  final String deviceId;
  final AsyncValue<ApiDeviceDetail> detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(doorCommandProvider(deviceId));
    final command = action.state;
    final isOwner = detail.value?.role == DeviceRole.owner;
    final cooldown = command.retryAfter != null;
    final enabled = isOwner && !command.busy && !cooldown;
    final subtitle = !isOwner
        ? 'Somente o proprietário pode enviar esta solicitação.'
        : switch (command.phase) {
            DoorCommandPhase.sending => 'Enviando solicitação…',
            DoorCommandPhase.waiting => 'Aguardando resposta do dispositivo…',
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
                onPressed: !isOwner || command.busy
                    ? null
                    : action.retryCreateAfterTimeout,
                child: const Text('Tentar novamente'),
              )
            : Semantics(
                button: true,
                enabled: enabled,
                label: 'Enviar solicitação para abrir porta',
                child: Tooltip(
                  message: enabled ? 'Abrir porta' : 'Ação indisponível',
                  child: FilledButton(
                    onPressed: enabled
                        ? () => _confirmAndStart(context, action)
                        : null,
                    child: const Text('Abrir'),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmAndStart(
    BuildContext context,
    DoorCommandActionController action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abrir porta?'),
        content: const Text(
          'O InterBridge enviará uma solicitação ao dispositivo. A abertura só será confirmada após a resposta do aparelho.',
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
    if (confirmed == true && context.mounted) {
      await action.start();
    }
  }
}

class _DetailCard extends ConsumerWidget {
  const _DetailCard({required this.deviceId, required this.detail});
  final String deviceId;
  final AsyncValue<ApiDeviceDetail> detail;
  @override
  Widget build(BuildContext context, WidgetRef ref) => detail.when(
    loading: () => const Card(
      child: ListTile(
        title: Text('Carregando dispositivo...'),
        trailing: CircularProgressIndicator(),
      ),
    ),
    error: (_, _) => Card(
      child: ListTile(
        title: const Text('Recurso indisponível'),
        subtitle: const Text('Não foi possível acessar este dispositivo.'),
        trailing: IconButton(
          onPressed: () => ref.invalidate(apiDeviceDetailProvider(deviceId)),
          icon: const Icon(Icons.refresh),
          tooltip: 'Tentar novamente',
        ),
      ),
    ),
    data: (device) => Card(
      child: ListTile(
        leading: const Icon(Icons.speaker_phone),
        title: Text(device.displayName ?? 'Meu InterBridge'),
        subtitle: Text(
          'Hardware: ${device.hardwareVersion ?? 'não informado'}\nAcesso: ${device.role.name.toUpperCase()}',
        ),
      ),
    ),
  );
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.deviceId, required this.status});
  final String deviceId;
  final AsyncValue<ApiDeviceStatus> status;
  @override
  Widget build(BuildContext context, WidgetRef ref) => status.when(
    loading: () =>
        const Card(child: ListTile(title: Text('Carregando status...'))),
    error: (_, _) => Card(
      child: ListTile(
        title: const Text('Status indisponível'),
        trailing: IconButton(
          onPressed: () => ref.invalidate(apiDeviceStatusProvider(deviceId)),
          icon: const Icon(Icons.refresh),
          tooltip: 'Tentar novamente',
        ),
      ),
    ),
    data: (value) {
      final health = value.health;
      final details = health == null
          ? 'Freshness: ${value.freshness.name.toUpperCase()}\nTelemetria ainda não disponível.'
          : 'Freshness: ${value.freshness.name.toUpperCase()}\nFirmware: ${health.firmwareVersion}\nInterfone: ${health.intercomState}\nÚltima comunicação: ${health.lastSeenAt.toLocal()}';
      return Card(
        child: ListTile(
          leading: const Icon(Icons.monitor_heart_outlined),
          title: Text(
            'Conectividade: ${value.connectivity.name.toUpperCase()}',
          ),
          subtitle: Text(details),
        ),
      );
    },
  );
}
