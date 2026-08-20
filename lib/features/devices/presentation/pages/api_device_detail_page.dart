import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/api_device.dart';
import '../providers/api_devices_provider.dart';

/// Deep-linkable read-only device details and status page.
class ApiDeviceDetailPage extends ConsumerWidget {
  const ApiDeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(apiDeviceDetailProvider(deviceId));
    final status = ref.watch(apiDeviceStatusProvider(deviceId));
    return Scaffold(
      appBar: AppBar(title: const Text('InterBridge')),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DeviceDetailCard(
              deviceId: deviceId,
              detail: detail,
            ),
            const SizedBox(height: 12),
            _DeviceStatusCard(status: status),
            const _UnavailableCommandCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.refresh(apiDeviceDetailProvider(deviceId).future),
      ref.refresh(apiDeviceStatusProvider(deviceId).future),
    ]);
  }
}

class _DeviceDetailCard extends ConsumerWidget {
  const _DeviceDetailCard({required this.deviceId, required this.detail});

  final String deviceId;
  final AsyncValue<ApiDeviceDetail> detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Card(
        child: ListTile(
          title: const Text('Recurso indisponível'),
          subtitle: const Text('Não foi possível acessar este dispositivo.'),
          trailing: IconButton(
            tooltip: 'Tentar novamente',
            onPressed: () => ref.invalidate(
              apiDeviceDetailProvider(deviceId),
            ),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (device) => Card(
        child: ListTile(
          leading: const Icon(Icons.speaker_phone),
          title: Text(device.displayName ?? 'Meu InterBridge'),
          subtitle: Text(
            'Hardware: ${device.hardwareVersion ?? 'não informado'}\n'
            'Acesso: ${device.role.name.toUpperCase()}',
          ),
        ),
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({required this.status});

  final AsyncValue<ApiDeviceStatus> status;

  @override
  Widget build(BuildContext context) {
    return status.when(
      loading: () => const Card(
        child: ListTile(title: Text('Carregando status...')),
      ),
      error: (_, _) => const Card(
        child: ListTile(title: Text('Status indisponível')),
      ),
      data: _buildStatusCard,
    );
  }

  Widget _buildStatusCard(ApiDeviceStatus deviceStatus) {
    final health = deviceStatus.health;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(
          'Conectividade: ${deviceStatus.connectivity.name.toUpperCase()}',
        ),
        // A null health report is shown as unknown. No firmware, timestamp, or
        // intercom state is invented to make the card appear complete.
        subtitle: health == null
            ? const Text('Status UNKNOWN — telemetria ainda não disponível.')
            : Text(
                'Firmware: ${health.firmwareVersion}\n'
                'Interfone: ${health.intercomState}',
              ),
      ),
    );
  }
}

class _UnavailableCommandCard extends StatelessWidget {
  const _UnavailableCommandCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        enabled: false,
        leading: Icon(Icons.lock_outline),
        title: Text('Abrir porta'),
        subtitle: Text(
          'Indisponível nesta fase. Nenhum comando será enviado.',
        ),
      ),
    );
  }
}
