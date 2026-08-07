import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/pages/dialer_page.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/presentation/providers/device_status_provider.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/presentation/pages/favorites_page.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({
    super.key,
    required this.device,
    required this.favoritesRepository,
  });

  final InterBridgeDevice device;
  final LocalFavoritesRepository favoritesRepository;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
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
    final pages = [
      _DeviceOverview(device: widget.device),
      DialerPage(controller: _dialerController),
      FavoritesPage(
        repository: widget.favoritesRepository,
        deviceId: widget.device.id,
        onDialFavorite: _dialFavorite,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Resumo',
          ),
          NavigationDestination(
            icon: Icon(Icons.dialpad_outlined),
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
  const _DeviceOverview({required this.device});
  final InterBridgeDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(deviceStatusProvider(device.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusHeader(status: status),
                const SizedBox(height: 16),
                _FirmwareStatus(status: status),
                _LastSeenStatus(status: status),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Eventos recentes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.history),
            title: Text('Nenhum evento recebido'),
            subtitle: Text(
              'Os eventos aparecerão quando o dispositivo estiver conectado.',
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status});
  final AsyncValue<DeviceStatus> status;

  @override
  Widget build(BuildContext context) => status.when(
        data: (value) => Row(
          children: [
            Icon(
              Icons.circle,
              color: value.isOnline ? Colors.green : Colors.grey,
              size: 12,
            ),
            const SizedBox(width: 8),
            Text(value.isOnline ? 'Online' : 'Aguardando conexão'),
          ],
        ),
        error: (_, _) => const _OfflineStatus(),
        loading: _OfflineStatus.new,
      );
}

class _OfflineStatus extends StatelessWidget {
  const _OfflineStatus();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          Icon(Icons.circle, color: Colors.grey, size: 12),
          SizedBox(width: 8),
          Text('Aguardando conexão'),
        ],
      );
}

class _FirmwareStatus extends StatelessWidget {
  const _FirmwareStatus({required this.status});
  final AsyncValue<DeviceStatus> status;

  @override
  Widget build(BuildContext context) {
    final firmware = status.valueOrNull?.firmwareVersion;
    return Text(
      firmware == null
          ? 'Firmware ainda não identificado'
          : 'Firmware: $firmware',
    );
  }
}

class _LastSeenStatus extends StatelessWidget {
  const _LastSeenStatus({required this.status});
  final AsyncValue<DeviceStatus> status;

  @override
  Widget build(BuildContext context) {
    final lastSeen = status.valueOrNull?.lastSeen;
    if (lastSeen == null) return const SizedBox.shrink();
    final localTime = lastSeen.toLocal();
    final formatted = '${localTime.day.toString().padLeft(2, '0')}/'
        '${localTime.month.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text('Última conexão: $formatted'),
    );
  }
}
