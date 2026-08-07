import 'package:flutter/material.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/pages/dialer_page.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
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

class _DeviceOverview extends StatelessWidget {
  const _DeviceOverview({required this.device});
  final InterBridgeDevice device;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.grey, size: 12),
                      SizedBox(width: 8),
                      Text('Aguardando conexão'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Firmware: ${device.firmware ?? 'Ainda não identificado'}'),
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
              subtitle: Text('Os eventos aparecerão quando o dispositivo estiver conectado.'),
            ),
          ),
        ],
      );
}
