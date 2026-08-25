import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/biometric_lock_gate.dart';
import '../../../devices/domain/entities/api_device.dart';
import '../../../devices/presentation/device_status_presentation.dart';
import '../../../devices/presentation/providers/api_devices_provider.dart';
import '../../../devices/presentation/providers/devices_providers.dart';
import '../../../profile/presentation/pages/registration_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';

/// Authenticated shell. Registered devices always come from the API; only
/// profile and other explicitly local preferences are stored on the phone.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _selectedIndex = 0;
  String? _profileName;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await ref.read(profileRepositoryProvider).getName();
    if (mounted) setState(() => _profileName = name);
  }

  Future<void> _editProfile() async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegistrationPage(initialName: _profileName),
      ),
    );
    if (name != null && mounted) setState(() => _profileName = name);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do InterBridge?'),
        content: const Text('Você precisará entrar novamente para continuar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    return BiometricLockGate(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedIndex == 0 ? 'Dispositivos' : 'Ajustes'),
        ),
        body: SafeArea(
          child: _selectedIndex == 0
              ? const _ApiDevicesTab()
              : SettingsPage(
                  profileName: _profileName,
                  onEditProfile: _editProfile,
                  onSecurity: () => context.push('/security'),
                  onLogout: _confirmLogout,
                ),
        ),
        floatingActionButton: _selectedIndex == 0
            ? FloatingActionButton.extended(
                onPressed: () => context.push('/add-interbridge'),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar/Parear'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (value) =>
              setState(() => _selectedIndex = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.speaker_phone_outlined),
              selectedIcon: Icon(Icons.speaker_phone),
              label: 'Dispositivos',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiDevicesTab extends ConsumerWidget {
  const _ApiDevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apiDevicesProvider);
    final controller = ref.read(apiDevicesProvider.notifier);
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.error != null) {
      return _InitialError(onRetry: controller.refresh);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: state.items.isEmpty
          ? const _EmptyDeviceList()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  if (state.loadMoreError != null) {
                    return TextButton(
                      onPressed: controller.loadMore,
                      child: const Text(
                        'Falha ao carregar mais. Tentar novamente',
                      ),
                    );
                  }
                  if (state.nextCursor == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      onPressed: state.loadingMore ? null : controller.loadMore,
                      child: Text(
                        state.loadingMore ? 'Carregando...' : 'Carregar mais',
                      ),
                    ),
                  );
                }
                return _DeviceTile(device: state.items[index]);
              },
            ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final ApiDeviceSummary device;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.speaker_phone)),
      title: Text(device.safeName),
      subtitle: Text(friendlyDeviceRole(device.role)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          context.push('/devices/${Uri.encodeComponent(device.deviceId)}'),
    ),
  );
}

class _EmptyDeviceList extends StatelessWidget {
  const _EmptyDeviceList();
  @override
  Widget build(BuildContext context) => ListView(
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

class _InitialError extends StatelessWidget {
  const _InitialError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
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
