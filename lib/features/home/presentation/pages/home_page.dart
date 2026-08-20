import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/biometric_lock_gate.dart';
import '../../../devices/domain/entities/api_device.dart';
import '../../../devices/presentation/providers/api_devices_provider.dart';

/// Authenticated home screen backed by the read-only device API.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceList = ref.watch(apiDevicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('InterBridge'),
        actions: [
          IconButton(
            tooltip: 'Segurança',
            onPressed: () => context.push('/security'),
            icon: const Icon(Icons.security),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BiometricLockGate(
        child: SafeArea(child: _DeviceListBody(state: deviceList)),
      ),
    );
  }
}

class _DeviceListBody extends ConsumerWidget {
  const _DeviceListBody({required this.state});

  final DeviceListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(apiDevicesProvider.notifier);
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _InitialError(onRetry: controller.refresh);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: state.items.isEmpty
          ? const _EmptyDeviceList()
          : _DeviceList(state: state),
    );
  }
}

class _EmptyDeviceList extends StatelessWidget {
  const _EmptyDeviceList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 160),
        Icon(Icons.speaker_phone, size: 64),
        Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum InterBridge disponível.'),
          ),
        ),
      ],
    );
  }
}

class _DeviceList extends ConsumerWidget {
  const _DeviceList({required this.state});

  final DeviceListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.items.length + 1,
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return _PaginationFooter(state: state);
        }
        return _DeviceTile(device: state.items[index]);
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final ApiDeviceSummary device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.speaker_phone)),
        title: Text(device.safeName),
        subtitle: Text(device.role.name.toUpperCase()),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final encodedDeviceId = Uri.encodeComponent(device.deviceId);
          context.push('/devices/$encodedDeviceId');
        },
      ),
    );
  }
}

class _PaginationFooter extends ConsumerWidget {
  const _PaginationFooter({required this.state});

  final DeviceListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadMore = ref.read(apiDevicesProvider.notifier).loadMore;
    if (state.loadMoreError != null) {
      return TextButton(
        onPressed: loadMore,
        child: const Text('Falha ao carregar mais. Tentar novamente'),
      );
    }
    if (state.nextCursor == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton(
        onPressed: state.loadingMore ? null : loadMore,
        child: Text(state.loadingMore ? 'Carregando...' : 'Carregar mais'),
      ),
    );
  }
}

class _InitialError extends StatelessWidget {
  const _InitialError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar seus dispositivos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
