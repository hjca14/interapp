import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialer/presentation/controllers/dialer_controller.dart';
import '../../../dialer/presentation/pages/dialer_page.dart';
import '../../../favorites/presentation/pages/favorites_page.dart';
import '../../domain/entities/api_device.dart';
import '../device_status_presentation.dart';
import '../widgets/door_command_card.dart';
import 'device_settings_page.dart';
import 'edit_device_name_page.dart';
import '../providers/api_devices_provider.dart';
import '../providers/devices_providers.dart';
import '../providers/device_refresh_provider.dart';

/// Observes routes covering the detail page so polling only runs while the
/// page is actually visible. Applications and widget tests must attach this
/// observer to their Navigator.
final deviceDetailRouteObserver = RouteObserver<ModalRoute<void>>();

/// The single device experience: backend-authoritative summary/status plus
/// local-only dialer, favorites and preferences scoped to the real device id.
class ApiDeviceDetailPage extends ConsumerStatefulWidget {
  const ApiDeviceDetailPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<ApiDeviceDetailPage> createState() =>
      _ApiDeviceDetailPageState();
}

class _ApiDeviceDetailPageState extends ConsumerState<ApiDeviceDetailPage>
    with WidgetsBindingObserver, RouteAware {
  final _dialerController = DialerController();
  int _selectedIndex = 0;
  StatusPollingHandle? _statusTimer;
  bool _refreshing = false;
  bool _routeVisible = true;
  bool _appResumed = true;
  ModalRoute<void>? _route;

  void _dialFavorite(String number) {
    _dialerController.setNumber(number);
    setState(() => _selectedIndex = 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route == route) return;
    if (_route != null) deviceDetailRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) deviceDetailRouteObserver.subscribe(this, route);
  }

  void _startPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (!_routeVisible || !_appResumed) return;
    _statusTimer = ref.read(statusPollingSchedulerProvider).periodic(
      const Duration(seconds: 60),
      () {
        _refreshStatus();
      },
    );
  }

  Future<void> _refreshStatus() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      await ref
          .read(deviceRefreshCoordinatorProvider(widget.deviceId))
          .refreshStatus();
    } on Object {
      // Automatic refresh is intentionally quiet. The existing status remains
      // visible; explicit refresh actions provide friendly error feedback.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _startPolling();
      if (_routeVisible) _refreshStatus();
    } else {
      _appResumed = false;
      _statusTimer?.cancel();
      _statusTimer = null;
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    if (!_appResumed) return;
    _startPolling();
    _refreshStatus();
  }

  @override
  void dispose() {
    deviceDetailRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _dialerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(apiDeviceDetailProvider(widget.deviceId));
    // Reused immediately while the detail GET this page kicked off is still
    // in flight, so a device tapped from the list never shows the
    // "InterBridge" domain fallback as if it were the confirmed name — see
    // `resolveKnownDeviceName`. No extra HTTP call: this reads the already
    // -loaded `apiDevicesProvider` list state.
    final knownName = knownDeviceName(
      ref.watch(apiDevicesProvider),
      widget.deviceId,
    );
    final title =
        resolveKnownDeviceName(
          detailLoaded: detail.hasValue,
          confirmedDisplayName: detail.value?.displayName,
          knownName: knownName,
        ) ??
        'Dispositivo';
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
                  knownName: knownName,
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

class _DeviceOverview extends ConsumerStatefulWidget {
  const _DeviceOverview({required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<_DeviceOverview> createState() => _DeviceOverviewState();
}

class _DeviceOverviewState extends ConsumerState<_DeviceOverview> {
  ApiDeviceStatus? _lastStatus;
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await ref
          .read(deviceRefreshCoordinatorProvider(widget.deviceId))
          .refreshAll();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar agora. Tente novamente.'),
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(apiDeviceDetailProvider(widget.deviceId));
    final status = ref.watch(apiDeviceStatusProvider(widget.deviceId));
    if (status.value case final value?) _lastStatus = value;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DetailCard(deviceId: widget.deviceId, detail: detail),
          const SizedBox(height: 12),
          _StatusCard(
            deviceId: widget.deviceId,
            status: status,
            lastStatus: _lastStatus,
          ),
          const SizedBox(height: 12),
          DoorCommandCard(deviceId: widget.deviceId, detail: detail),
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
    data: (device) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.speaker_phone),
          title: Text(deviceDisplayName(device.displayName)),
          trailing: IconButton(
            tooltip: 'Editar nome',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditDeviceNamePage(
                  deviceId: deviceId,
                  initialName: device.displayName,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({
    required this.deviceId,
    required this.status,
    required this.lastStatus,
  });
  final String deviceId;
  final AsyncValue<ApiDeviceStatus> status;
  final ApiDeviceStatus? lastStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = status.value ?? lastStatus;
    final presentation = DeviceStatusPresentation.from(value);
    // Same known-name reuse as the AppBar above — never a hardcoded
    // "InterBridge" standing in for a name that just hasn't loaded yet.
    final knownName = knownDeviceName(ref.watch(apiDevicesProvider), deviceId);
    return Card(
      child: ListTile(
        leading: Icon(presentation.icon, color: presentation.color(context)),
        title: Text(presentation.label),
        subtitle: Text(
          value?.health == null
              ? 'Última comunicação não informada'
              : formatLastCommunication(
                  value!.health!.lastSeenAt,
                  DateTime.now(),
                ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceSettingsPage(
              deviceId: deviceId,
              knownName: knownName,
              initialSection: DeviceSettingsSection.diagnostics,
            ),
          ),
        ),
      ),
    );
  }
}
