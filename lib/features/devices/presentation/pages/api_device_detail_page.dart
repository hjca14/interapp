import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialer/presentation/controllers/dialer_controller.dart';
import '../../../dialer/presentation/pages/dialer_page.dart';
import '../../../favorites/presentation/pages/favorites_page.dart';
import '../../../commands/presentation/providers/door_command_provider.dart';
import '../../../sharing/domain/entities/device_access.dart';
import '../../../auth/domain/services/biometric_lock.dart';
import '../../../auth/presentation/providers/biometric_lock_providers.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/entities/device_settings.dart';
import '../device_status_presentation.dart';
import 'device_settings_page.dart';
import '../providers/api_devices_provider.dart';
import '../providers/devices_providers.dart';
import '../providers/device_settings_provider.dart';
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
          _DoorCommandCard(deviceId: widget.deviceId, detail: detail),
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

class _DoorCommandCard extends ConsumerStatefulWidget {
  const _DoorCommandCard({required this.deviceId, required this.detail});

  final String deviceId;
  final AsyncValue<ApiDeviceDetail> detail;

  @override
  ConsumerState<_DoorCommandCard> createState() => _DoorCommandCardState();
}

class _DoorCommandCardState extends ConsumerState<_DoorCommandCard>
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
                onPressed:
                    !isOwner ||
                        !settingsReady ||
                        command.busy ||
                        cooldown ||
                        cancelled
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
                        ? () => _prepareAndStart(action, settings)
                        : null,
                    child: const Text('Abrir'),
                  ),
                ),
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
    final authenticator = ref.read(doorDeviceAuthenticatorProvider);
    try {
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
              deviceName: 'InterBridge',
              initialSection: DeviceSettingsSection.diagnostics,
            ),
          ),
        ),
      ),
    );
  }
}
