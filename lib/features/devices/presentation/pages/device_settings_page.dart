import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/presentation/providers/device_settings_provider.dart';

/// Per-device behavior preferences, reached from `DeviceDetailPage`'s app
/// bar. Everything here is a local preference the app itself will act on
/// later — nothing here talks to real hardware yet (no Wi-Fi change,
/// firmware, reboot, biometrics, or door command are actually performed).
class DeviceSettingsPage extends ConsumerWidget {
  const DeviceSettingsPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const _DeviceCard(),
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
/// here. Biometric/Face ID enforcement itself isn't implemented; this only
/// reserves the flag for the door-open flow to check later.
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
            'Vai pedir a senha ou biometria do celular para abrir (em breve).',
          ),
          value: settings.requireDeviceAuthenticationToOpenDoor,
          onChanged: onAuthChanged,
        ),
      ],
    );
  }
}

/// Placeholders for Wi-Fi/firmware/diagnóstico/reiniciar — real hardware
/// features that don't exist yet. Reuses the same "not implemented yet"
/// snackbar pattern as the dialer's call button instead of disabling the
/// rows outright, so the user gets feedback instead of a dead tap.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  static const _items = ['Wi-Fi', 'Firmware', 'Diagnóstico', 'Reiniciar'];

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      icon: Icons.router_outlined,
      title: 'Dispositivo',
      children: _items
          .map(
            (label) => ListTile(
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Disponível quando o InterBridge estiver conectado.',
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
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
