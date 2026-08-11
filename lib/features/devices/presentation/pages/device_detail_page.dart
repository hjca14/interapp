import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/pages/dialer_page.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/domain/entities/device_event.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/presentation/pages/device_settings_page.dart';
import 'package:interapp/features/devices/presentation/providers/device_command_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_events_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_status_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/devices/presentation/widgets/incoming_call_listener.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/presentation/pages/favorites_page.dart';

/// The screen for one device: Resumo / Discar / Favoritos tabs, plus the
/// incoming-call reaction wired around all three (see [IncomingCallListener]).
///
/// A [ConsumerStatefulWidget] rather than a plain [StatefulWidget] so its
/// state can `ref.read` providers directly (used by the debug "simulate
/// call" button below).
class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({
    super.key,
    required this.device,
    required this.favoritesRepository,
  });

  final InterBridgeDevice device;
  final LocalFavoritesRepository favoritesRepository;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  /// Shared with [DialerPage] so a favorite tapped from the Favoritos tab can
  /// fill the number here without the tabs needing to talk to each other
  /// directly.
  final _dialerController = DialerController();
  int _selectedIndex = 0;

  /// Called by [FavoritesPage] when a favorite is tapped: fills the number
  /// and jumps to the Discar tab (index 1).
  void _dialFavorite(String number) {
    _dialerController.setNumber(number);
    setState(() => _selectedIndex = 1);
  }

  /// Debug-only action behind the [kDebugMode] button in the app bar. Only
  /// does anything when the active repository is the local/prototype one —
  /// a real transport wouldn't understand `simulateIncomingCall`.
  void _simulateIncomingCall() {
    final repository = ref.read(deviceConnectionRepositoryProvider);
    if (repository is LocalDeviceConnectionRepository) {
      repository.simulateIncomingCall(widget.device.id);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceSettingsPage(
          deviceId: widget.device.id,
          deviceName: widget.device.name,
        ),
      ),
    );
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
    return IncomingCallListener(
      deviceId: widget.device.id,
      deviceName: widget.device.name,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.name),
          actions: [
            if (kDebugMode)
              IconButton(
                tooltip: 'Simular chamada (debug)',
                icon: const Icon(Icons.phone_callback_outlined),
                onPressed: _simulateIncomingCall,
              ),
            IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openSettings,
            ),
          ],
        ),
        body: SafeArea(child: pages[_selectedIndex]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
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
      ),
    );
  }
}

/// The "Resumo" tab: connection status, firmware, last-seen time, and a
/// placeholder for recent events. Reads live status from
/// [deviceStatusProvider] rather than holding its own [DeviceStatus].
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
        const SizedBox(height: 16),
        _OpenDoorCard(deviceId: device.id),
        const SizedBox(height: 24),
        Text('Eventos recentes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _EventsCard(deviceId: device.id),
      ],
    );
  }
}

/// The "Abrir porta" action, wired to [deviceCommandControllerProvider]'s
/// `OPEN_DOOR` state machine. Never marks success just because the async
/// call returned — only `DeviceCommandStatus.completed` does, and a `200`-
/// equivalent response alone never gets there with today's stub backend.
class _OpenDoorCard extends ConsumerWidget {
  const _OpenDoorCard({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceCommandControllerProvider(deviceId));
    final controller = ref.read(
      deviceCommandControllerProvider(deviceId).notifier,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.lock_open_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Abrir porta'),
                  const SizedBox(height: 2),
                  Text(
                    _openDoorStatusLabel(state),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: state.isBusy ? null : controller.openDoor,
              child: state.isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Abrir'),
            ),
          ],
        ),
      ),
    );
  }
}

String _openDoorStatusLabel(OpenDoorRequestState state) {
  switch (state.phase) {
    case OpenDoorRequestPhase.idle:
      return 'Toque para abrir a porta do InterBridge.';
    case OpenDoorRequestPhase.sending:
      return 'Enviando comando...';
    case OpenDoorRequestPhase.accepted:
      return 'Comando aceito, aguardando o InterBridge executar...';
    case OpenDoorRequestPhase.completed:
      return 'Porta aberta.';
    case OpenDoorRequestPhase.failed:
    case OpenDoorRequestPhase.rejected:
      return state.error != null
          ? deviceProtocolErrorMessage(state.error!)
          : 'Não foi possível abrir a porta.';
    case OpenDoorRequestPhase.timedOut:
      return 'O InterBridge não respondeu a tempo. Tente novamente.';
  }
}

/// Recent events for this device, backed by [deviceEventsProvider]. Shows
/// "Nenhum evento recebido" for both the loading state and a genuinely
/// empty history — today's stub backend always returns an empty list, so
/// this keeps showing the same honest placeholder until a real backend
/// reports something.
class _EventsCard extends ConsumerWidget {
  const _EventsCard({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(deviceEventsProvider(deviceId));
    final events = eventsAsync.when(
      data: (events) => events,
      loading: () => const <DeviceEvent>[],
      error: (_, _) => const <DeviceEvent>[],
    );
    if (events.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.history),
          title: Text('Nenhum evento recebido'),
          subtitle: Text(
            'Os eventos aparecerão quando o dispositivo estiver conectado.',
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: events
            .map(
              (event) => ListTile(
                leading: const Icon(Icons.history),
                title: Text(event.type.name),
                subtitle: event.timestamp != null
                    ? Text(event.timestamp!.toLocal().toString())
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// The green/grey dot + "Online"/"Aguardando conexão" line at the top of the
/// overview card. Falls back to [_OfflineStatus] on both `loading` and
/// `error` — the UI never guesses "online" while unsure.
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

/// Static "not connected" row, reused for the loading, error and genuinely
/// offline cases so they all look identical to the user.
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

/// Shows the firmware version once known, or an honest "not identified yet"
/// placeholder instead of a made-up version string.
class _FirmwareStatus extends StatelessWidget {
  const _FirmwareStatus({required this.status});
  final AsyncValue<DeviceStatus> status;

  @override
  Widget build(BuildContext context) {
    final firmware = _statusValue(status)?.firmwareVersion;
    return Text(
      firmware == null
          ? 'Firmware ainda não identificado'
          : 'Firmware: $firmware',
    );
  }
}

/// Shows "Última conexão: dd/mm hh:mm" when [DeviceStatus.lastSeen] is
/// known, or collapses to nothing (`SizedBox.shrink`) when it isn't — no row
/// is better than a fake timestamp.
class _LastSeenStatus extends StatelessWidget {
  const _LastSeenStatus({required this.status});
  final AsyncValue<DeviceStatus> status;

  @override
  Widget build(BuildContext context) {
    final lastSeen = _statusValue(status)?.lastSeen;
    if (lastSeen == null) return const SizedBox.shrink();
    final localTime = lastSeen.toLocal();
    final formatted =
        '${localTime.day.toString().padLeft(2, '0')}/'
        '${localTime.month.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text('Última conexão: $formatted'),
    );
  }
}

/// Unwraps an `AsyncValue<DeviceStatus>` to its data, or `null` on loading/
/// error — a small helper so [_FirmwareStatus] and [_LastSeenStatus] don't
/// each repeat the same `.when(...)` boilerplate.
DeviceStatus? _statusValue(AsyncValue<DeviceStatus> status) {
  return status.when(
    data: (value) => value,
    error: (_, _) => null,
    loading: () => null,
  );
}
