import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/device_status_presentation.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_refresh_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_settings_provider.dart';

enum DeviceSettingsSection { main, firmware, diagnostics }

/// Per-device behavior preferences, reached from `DeviceDetailPage`'s app
/// bar. Everything here is a local preference the app itself will act on
/// later — nothing here talks to real hardware yet (no Wi-Fi change,
/// firmware, reboot, biometrics, or door command are actually performed).
class DeviceSettingsPage extends ConsumerWidget {
  const DeviceSettingsPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.initialSection = DeviceSettingsSection.main,
  });

  final String deviceId;
  final String deviceName;
  final DeviceSettingsSection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSection == DeviceSettingsSection.firmware) {
      return FirmwarePage(deviceId: deviceId);
    }
    if (initialSection == DeviceSettingsSection.diagnostics) {
      return DiagnosticsPage(deviceId: deviceId);
    }
    final settingsAsync = ref.watch(deviceSettingsProvider(deviceId));
    return Scaffold(
      appBar: AppBar(title: Text('Configurações de $deviceName')),
      body: settingsAsync.when(
        data: (settings) => _DeviceSettingsBody(
          deviceId: deviceId,
          deviceName: deviceName,
          settings: settings,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Não foi possível carregar as configurações deste dispositivo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceSettingsBody extends ConsumerWidget {
  const _DeviceSettingsBody({
    required this.deviceId,
    required this.deviceName,
    required this.settings,
  });

  final String deviceId;
  final String deviceName;
  final DeviceSettings settings;

  /// Every card below reads from [settings] and writes through this — one
  /// call site that applies an edit to the whole [DeviceSettings] and
  /// persists it via `DeviceSettingsController`.
  void _apply(
    WidgetRef ref,
    DeviceSettings Function(DeviceSettings current) updater,
  ) {
    ref.read(deviceSettingsProvider(deviceId).notifier).updateSettings(updater);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CallsCard(
          mode: settings.calls.localNetworkAlertMode,
          onChanged: (mode) => _apply(
            ref,
            (current) => current.copyWith(
              calls: current.calls.copyWith(localNetworkAlertMode: mode),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _QuietHoursCard(
          settings: settings.quietHours,
          onChanged: (quietHours) => _apply(
            ref,
            (current) => current.copyWith(quietHours: quietHours),
          ),
        ),
        const SizedBox(height: 16),
        _PresenceCard(
          calls: settings.calls,
          onRemoteModeChanged: (mode) => _apply(
            ref,
            (current) => current.copyWith(
              calls: current.calls.copyWith(remoteNetworkAlertMode: mode),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _DoorCard(
          settings: settings,
          onConfirmChanged: (value) => _apply(
            ref,
            (current) => current.copyWith(confirmBeforeOpeningDoor: value),
          ),
          onAuthChanged: (value) => _apply(
            ref,
            (current) =>
                current.copyWith(requireDeviceAuthenticationToOpenDoor: value),
          ),
        ),
        const SizedBox(height: 16),
        _DeviceCard(deviceId: deviceId),
        const SizedBox(height: 16),
        _AdvancedCard(deviceId: deviceId, deviceName: deviceName),
      ],
    );
  }
}

/// A titled card wrapping one settings group, matching the section headers
/// from the feature spec (Chamadas, Silencioso, Presença, Porta, Dispositivo,
/// Avançado) without reproducing their exact mockup styling.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// "Receber ligação" and "Receber notificação" for the local-network
/// (default/home) behavior — two familiar switches that combine into one
/// [CallAlertMode] under the hood instead of two independent booleans.
class _CallsCard extends StatelessWidget {
  const _CallsCard({required this.mode, required this.onChanged});

  final CallAlertMode mode;
  final ValueChanged<CallAlertMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.call_outlined,
      title: 'Chamadas',
      children: [
        SwitchListTile(
          title: const Text('Receber ligação'),
          subtitle: const Text(
            'Toca e abre a tela de chamada ao receber uma chamada.',
          ),
          value: mode.includesRing,
          onChanged: (ring) => onChanged(
            CallAlertMode.from(
              ring: ring,
              notification: mode.includesNotification,
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Receber notificação'),
          subtitle: const Text(
            'Mostra uma notificação ao receber uma chamada.',
          ),
          value: mode.includesNotification,
          onChanged: (notification) => onChanged(
            CallAlertMode.from(
              ring: mode.includesRing,
              notification: notification,
            ),
          ),
        ),
      ],
    );
  }
}

/// Behavior per [NetworkPresence]: local is shown read-only here (it's
/// edited in the Chamadas card above); remote is the actual "receber
/// chamadas fora da rede local" preference, modeled as a full
/// [CallAlertMode] picker instead of a single on/off switch.
class _PresenceCard extends StatelessWidget {
  const _PresenceCard({required this.calls, required this.onRemoteModeChanged});

  final DeviceCallSettings calls;
  final ValueChanged<CallAlertMode> onRemoteModeChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.home_outlined,
      title: 'Presença',
      children: [
        ListTile(
          title: const Text('Na rede local'),
          subtitle: Text(
            '${_callAlertModeLabel(calls.localNetworkAlertMode)} · configurado em Chamadas',
          ),
        ),
        ListTile(
          title: const Text('Fora da rede local'),
          subtitle: const Text(
            'O que fazer quando o InterBridge perceber que você não está na rede local.',
          ),
          trailing: DropdownButton<CallAlertMode>(
            value: calls.remoteNetworkAlertMode,
            onChanged: (mode) {
              if (mode != null) {
                onRemoteModeChanged(mode);
              }
            },
            items: CallAlertMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(_callAlertModeLabel(mode)),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

String _callAlertModeLabel(CallAlertMode mode) {
  switch (mode) {
    case CallAlertMode.none:
      return 'Nenhuma';
    case CallAlertMode.ringOnly:
      return 'Só ligação';
    case CallAlertMode.notificationOnly:
      return 'Só notificação';
    case CallAlertMode.ringAndNotification:
      return 'Ligação e notificação';
  }
}

const _weekdayLabels = {
  DateTime.monday: 'Seg',
  DateTime.tuesday: 'Ter',
  DateTime.wednesday: 'Qua',
  DateTime.thursday: 'Qui',
  DateTime.friday: 'Sex',
  DateTime.saturday: 'Sáb',
  DateTime.sunday: 'Dom',
};

String _formatClockTime(ClockTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Do-not-disturb window: on/off, start/end time, days of the week, and what
/// happens to alerts while it's active. The time/weekday/behavior controls
/// only show once [QuietHoursSettings.enabled] is on, to keep the card short
/// the rest of the time.
class _QuietHoursCard extends StatelessWidget {
  const _QuietHoursCard({required this.settings, required this.onChanged});

  final QuietHoursSettings settings;
  final ValueChanged<QuietHoursSettings> onChanged;

  Future<void> _pickTime(BuildContext context, {required bool isStart}) async {
    final initial = isStart ? settings.start : settings.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (picked == null) {
      return;
    }
    final clockTime = ClockTime(hour: picked.hour, minute: picked.minute);
    onChanged(
      isStart
          ? settings.copyWith(start: clockTime)
          : settings.copyWith(end: clockTime),
    );
  }

  void _toggleWeekday(int day) {
    final updated = Set<int>.from(settings.weekdays);
    if (!updated.remove(day)) {
      updated.add(day);
    }
    onChanged(settings.copyWith(weekdays: updated));
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.nightlight_round,
      title: 'Silencioso',
      children: [
        SwitchListTile(
          title: const Text('Modo silencioso'),
          value: settings.enabled,
          onChanged: (value) => onChanged(settings.copyWith(enabled: value)),
        ),
        if (settings.enabled) ...[
          ListTile(
            title: const Text('Horário'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _pickTime(context, isStart: true),
                  child: Text(_formatClockTime(settings.start)),
                ),
                const Text('—'),
                TextButton(
                  onPressed: () => _pickTime(context, isStart: false),
                  child: Text(_formatClockTime(settings.end)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _weekdayLabels.entries.map((entry) {
                return FilterChip(
                  label: Text(entry.value),
                  selected: settings.weekdays.contains(entry.key),
                  onSelected: (_) => _toggleWeekday(entry.key),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<QuietHoursBehavior>(
              segments: const [
                ButtonSegment(
                  value: QuietHoursBehavior.blockAll,
                  label: Text('Bloquear tudo'),
                ),
                ButtonSegment(
                  value: QuietHoursBehavior.silentNotificationOnly,
                  label: Text('Notificação sem som'),
                ),
              ],
              selected: {settings.behavior},
              onSelectionChanged: (selection) =>
                  onChanged(settings.copyWith(behavior: selection.first)),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Confirmar abertura" and "exigir autenticação" — both plain booleans
/// since, unlike the call policy, there's no meaningful combination to model
/// here. Device authentication is enforced by the door-open flow.
class _DoorCard extends StatelessWidget {
  const _DoorCard({
    required this.settings,
    required this.onConfirmChanged,
    required this.onAuthChanged,
  });

  final DeviceSettings settings;
  final ValueChanged<bool> onConfirmChanged;
  final ValueChanged<bool> onAuthChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.meeting_room_outlined,
      title: 'Porta',
      children: [
        SwitchListTile(
          title: const Text('Confirmar antes de abrir'),
          subtitle: const Text(
            'Pede confirmação antes de enviar o comando de abertura.',
          ),
          value: settings.confirmBeforeOpeningDoor,
          onChanged: onConfirmChanged,
        ),
        SwitchListTile(
          title: const Text('Exigir autenticação do aparelho'),
          subtitle: const Text(
            'Pede a credencial segura ou biometria do aparelho para abrir.',
          ),
          value: settings.requireDeviceAuthenticationToOpenDoor,
          onChanged: onAuthChanged,
        ),
      ],
    );
  }
}

/// Device information and actions. Firmware and diagnostics are honest,
/// read-only views; unsupported hardware actions retain explicit feedback.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.router_outlined,
      title: 'Dispositivo',
      children: [
        _UnavailableDeviceItem(label: 'Wi-Fi'),
        ListTile(
          title: const Text('Firmware'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => FirmwarePage(deviceId: deviceId)),
          ),
        ),
        ListTile(
          title: const Text('Diagnóstico'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DiagnosticsPage(deviceId: deviceId),
            ),
          ),
        ),
        _UnavailableDeviceItem(label: 'Reiniciar'),
      ],
    );
  }
}

class _UnavailableDeviceItem extends StatelessWidget {
  const _UnavailableDeviceItem({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disponível quando o InterBridge estiver conectado.'),
      ),
    ),
  );
}

class FirmwarePage extends ConsumerWidget {
  const FirmwarePage({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(apiDeviceStatusProvider(deviceId));
    final version = status.value?.health?.firmwareVersion ?? 'Não informada';
    return Scaffold(
      appBar: AppBar(title: const Text('Firmware')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: const Text('Versão atual'),
                  subtitle: Text(version),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Atualização OTA ainda não disponível'),
                  subtitle: Text(
                    'Quando esse recurso estiver disponível, ele aparecerá aqui.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  ApiDeviceStatus? _lastStatus;
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref
          .read(deviceRefreshCoordinatorProvider(widget.deviceId))
          .refreshStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnóstico atualizado.')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar o diagnóstico agora.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(apiDeviceStatusProvider(widget.deviceId));
    if (statusAsync.value case final value?) _lastStatus = value;
    final status = statusAsync.value ?? _lastStatus;
    final health = status?.health;
    final presentation = DeviceStatusPresentation.from(status);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    presentation.icon,
                    color: presentation.color(context),
                  ),
                  title: const Text('Status'),
                  subtitle: Text(presentation.label),
                ),
                ListTile(
                  title: const Text('Última comunicação'),
                  subtitle: Text(
                    health == null
                        ? 'Não informada'
                        : formatLastCommunication(
                            health.lastSeenAt,
                            DateTime.now(),
                          ),
                  ),
                ),
                ListTile(
                  title: const Text('Estado do interfone'),
                  subtitle: Text(
                    friendlyIntercomState(
                      health?.intercomState ?? IntercomState.unreported,
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Atualidade dos dados'),
                  subtitle: Text(
                    friendlyFreshness(
                      status?.freshness ?? DeviceFreshness.unknown,
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Identificador do dispositivo'),
                  subtitle: Text(_maskedDeviceId(widget.deviceId)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Atualizar diagnóstico'),
          ),
        ],
      ),
    );
  }
}

String _maskedDeviceId(String id) {
  final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
  return '••••$suffix';
}

/// The one action here that's actually implemented: resetting this device's
/// local settings back to defaults (no hardware factory-reset exists yet).
class _AdvancedCard extends ConsumerWidget {
  const _AdvancedCard({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redefinir configurações?'),
        content: Text(
          'Isso volta as configurações de "$deviceName" para os valores padrão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redefinir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(deviceSettingsProvider(deviceId).notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorColor = Theme.of(context).colorScheme.error;
    return _SettingsSection(
      icon: Icons.warning_amber_outlined,
      title: 'Avançado',
      children: [
        ListTile(
          leading: Icon(Icons.restart_alt, color: errorColor),
          title: Text(
            'Redefinir configurações',
            style: TextStyle(color: errorColor),
          ),
          onTap: () => _confirmReset(context, ref),
        ),
      ],
    );
  }
}
