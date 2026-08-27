import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/device_status_presentation.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_refresh_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_settings_provider.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

enum DeviceSettingsSection { main, firmware, diagnostics }

class DeviceSettingsPage extends ConsumerWidget {
  const DeviceSettingsPage({super.key, required this.deviceId, required this.deviceName, this.initialSection = DeviceSettingsSection.main});
  final String deviceId;
  final String deviceName;
  final DeviceSettingsSection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSection == DeviceSettingsSection.firmware) return FirmwarePage(deviceId: deviceId);
    if (initialSection == DeviceSettingsSection.diagnostics) return DiagnosticsPage(deviceId: deviceId);
    final local = ref.watch(deviceSettingsProvider(deviceId));
    return Scaffold(
      appBar: AppBar(title: Text('Configurações de $deviceName')),
      body: local.when(
        data: (settings) => _DeviceSettingsBody(deviceId: deviceId, deviceName: deviceName, settings: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Não foi possível carregar as preferências locais.')),
      ),
    );
  }
}

class _DeviceSettingsBody extends ConsumerWidget {
  const _DeviceSettingsBody({required this.deviceId, required this.deviceName, required this.settings});
  final String deviceId;
  final String deviceName;
  final DeviceSettings settings;

  void _apply(WidgetRef ref, DeviceSettings Function(DeviceSettings) update) =>
      ref.read(deviceSettingsProvider(deviceId).notifier).updateSettings(update);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _RemotePreferences(deviceId: deviceId),
      const SizedBox(height: 16),
      _DoorCard(
        settings: settings,
        onConfirmChanged: (value) => _apply(ref, (s) => s.copyWith(confirmBeforeOpeningDoor: value)),
        onAuthChanged: (value) => _apply(ref, (s) => s.copyWith(requireDeviceAuthenticationToOpenDoor: value)),
      ),
      const SizedBox(height: 16),
      _AccessCard(detail: ref.watch(apiDeviceDetailProvider(deviceId))),
      const SizedBox(height: 16),
      _DeviceCard(deviceId: deviceId),
      const SizedBox(height: 16),
      _AdvancedCard(deviceId: deviceId, deviceName: deviceName),
    ]);
  }
}

class _RemotePreferences extends ConsumerWidget {
  const _RemotePreferences({required this.deviceId});
  final String deviceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceNotificationPreferencesProvider(deviceId));
    final controller = ref.read(deviceNotificationPreferencesProvider(deviceId).notifier);
    if (state.draft == null) {
      return _SettingsSection(icon: Icons.notifications_outlined, title: 'Alertas', children: [
        if (state.phase == NotificationPreferencesPhase.loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          ListTile(title: const Text('Não foi possível carregar as preferências de alertas.'), subtitle: Text(state.message ?? 'Tente novamente.')),
          TextButton(onPressed: controller.load, child: const Text('Tentar novamente')),
        ],
      ]);
    }
    final draft = state.draft!;
    final saving = state.phase == NotificationPreferencesPhase.saving;
    void edit(DeviceNotificationPreferences value) => controller.edit((_) => value);
    return Column(children: [
      _AlertsCard(preferences: draft, enabled: !saving, onChanged: edit),
      const SizedBox(height: 16),
      _QuietScheduleCard(schedule: draft.quietSchedule, enabled: !saving, onEnabled: controller.enableSchedule,
        onChanged: (schedule) => edit(draft.copyWith(quietSchedule: schedule))),
      if (state.message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(state.message!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (state.phase == NotificationPreferencesPhase.conflict)
        ListTile(title: const Text('Estas preferências mudaram em outro lugar.'), subtitle: const Text('Recarregue os valores atuais antes de editar novamente.'), trailing: TextButton(onPressed: controller.load, child: const Text('Recarregar'))),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: state.hasChanges && !saving ? controller.discard : null, child: const Text('Descartar')),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: state.canSave ? controller.save : null,
          icon: saving ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Salvando...' : 'Salvar')),
      ]),
    ]);
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.preferences, required this.enabled, required this.onChanged});
  final DeviceNotificationPreferences preferences;
  final bool enabled;
  final ValueChanged<DeviceNotificationPreferences> onChanged;
  @override
  Widget build(BuildContext context) {
    final mode = preferences.alertMode;
    void change({bool? ring, bool? notification}) => onChanged(preferences.copyWith(alertMode: AlertMode.from(
      ring: ring ?? mode.includesRing, notification: notification ?? mode.includesNotification)));
    return _SettingsSection(icon: Icons.notifications_outlined, title: 'Alertas', children: [
      SwitchListTile(title: const Text('Receber ligação'), subtitle: const Text('Mostra a tela de chamada quando o interfone tocar.'), value: mode.includesRing, onChanged: enabled ? (value) => change(ring: value) : null),
      SwitchListTile(title: const Text('Receber notificação'), subtitle: const Text('Mostra uma notificação relacionada ao toque do interfone.'), value: mode.includesNotification, onChanged: enabled ? (value) => change(notification: value) : null),
      const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text('As preferências já ficam salvas. Elas passarão a controlar os alertas quando a integração de notificações for ativada.')),
    ]);
  }
}

const _weekdayLabels = {1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui', 5: 'Sex', 6: 'Sáb', 7: 'Dom'};

class _QuietScheduleCard extends StatelessWidget {
  const _QuietScheduleCard({required this.schedule, required this.enabled, required this.onEnabled, required this.onChanged});
  final QuietSchedule schedule;
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<QuietSchedule> onChanged;
  Future<void> _pick(BuildContext context, bool start) async {
    final value = start ? schedule.startTime : schedule.endTime;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: value?.hour ?? (start ? 22 : 7), minute: value?.minute ?? 0));
    if (picked == null) return;
    final time = ClockTime(picked.hour, picked.minute);
    onChanged(start ? schedule.copyWith(startTime: time) : schedule.copyWith(endTime: time));
  }
  @override
  Widget build(BuildContext context) => _SettingsSection(icon: Icons.schedule, title: 'Horários sem ligação', children: [
    SwitchListTile(title: const Text('Ativar horários sem ligação'), value: schedule.enabled, onChanged: enabled ? onEnabled : null),
    if (schedule.enabled) ...[
      ListTile(title: const Text('Horário'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [TextButton(onPressed: enabled ? () => _pick(context, true) : null, child: Text(schedule.startTime?.wireValue ?? '--:--')), const Text('—'), TextButton(onPressed: enabled ? () => _pick(context, false) : null, child: Text(schedule.endTime?.wireValue ?? '--:--'))])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 6, children: _weekdayLabels.entries.map((day) => FilterChip(label: Text(day.value), selected: schedule.days.contains(day.key), onSelected: enabled ? (_) { final days = Set<int>.from(schedule.days); days.remove(day.key) || days.add(day.key); onChanged(schedule.copyWith(days: days)); } : null)).toList())),
      ListTile(title: const Text('Fuso horário'), subtitle: Text(schedule.timezone ?? 'Indisponível')),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SegmentedButton<QuietScheduleBehavior>(segments: const [ButtonSegment(value: QuietScheduleBehavior.notificationOnly, label: Text('Só notificação')), ButtonSegment(value: QuietScheduleBehavior.blockAll, label: Text('Bloquear tudo'))], selected: {schedule.behavior}, onSelectionChanged: enabled ? (value) => onChanged(schedule.copyWith(behavior: value.first)) : null)),
      Padding(padding: const EdgeInsets.all(16), child: Text(schedule.behavior == QuietScheduleBehavior.notificationOnly ? 'Durante esse horário, o celular não tocará como ligação. A notificação continua disponível se estiver ativada em Alertas.' : 'Durante esse horário, ligações e notificações desse InterBridge não serão exibidas.')),
    ],
  ]);
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.detail});
  final AsyncValue<ApiDeviceDetail> detail;
  @override
  Widget build(BuildContext context) => _SettingsSection(icon: Icons.group_outlined, title: 'Acesso e compartilhamento', children: [detail.when(
    data: (device) => ListTile(title: const Text('Seu papel'), subtitle: Text('${friendlyDeviceRole(device.role)}\n${_sharingPermissionDescription(device.role)}'), isThreeLine: true),
    loading: () => const ListTile(title: Text('Seu papel'), subtitle: Text('Carregando informações de acesso...')),
    error: (_, _) => const ListTile(title: Text('Seu papel'), subtitle: Text('Informações de acesso indisponíveis.')),
  )]);
}
String _sharingPermissionDescription(DeviceRole role) => switch (role) { DeviceRole.owner || DeviceRole.admin => 'Você tem permissão para gerenciar o compartilhamento. Esse recurso ainda não está disponível.', DeviceRole.member => 'Você não tem permissão para compartilhar este dispositivo.' };

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.icon, required this.title, required this.children});
  final IconData icon; final String title; final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Row(children: [Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleMedium)])), ...children, const SizedBox(height: 4)]));
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

  Future<void> _showDeviceIdentifier() async {
    final shouldCopy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Identificador do dispositivo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use este identificador quando o suporte solicitar.'),
            const SizedBox(height: 12),
            SelectableText(widget.deviceId),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar identificador'),
          ),
        ],
      ),
    );
    if (shouldCopy != true) return;
    await Clipboard.setData(ClipboardData(text: widget.deviceId));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Identificador copiado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(apiDeviceStatusProvider(widget.deviceId));
    final detailAsync = ref.watch(apiDeviceDetailProvider(widget.deviceId));
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
                        : formatDiagnosticTimestamp(health.lastSeenAt),
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
                detailAsync.when(
                  data: (device) => Column(
                    children: [
                      ListTile(
                        title: const Text('Versão do hardware'),
                        subtitle: Text(
                          device.hardwareVersion ?? 'Não informada',
                        ),
                      ),
                      ListTile(
                        leading:
                            provisioningStatusNeedsAttention(
                              device.provisioningStatus,
                            )
                            ? Icon(
                                isProvisioningFailure(device.provisioningStatus)
                                    ? Icons.error_outline
                                    : Icons.warning_amber_outlined,
                                color: Theme.of(context).colorScheme.error,
                              )
                            : null,
                        title: const Text('Estado de configuração'),
                        subtitle: Text(
                          isProvisioningFailure(device.provisioningStatus)
                              ? '${friendlyProvisioningStatus(device.provisioningStatus)}. O suporte poderá orientar os próximos passos.'
                              : friendlyProvisioningStatus(
                                  device.provisioningStatus,
                                ),
                        ),
                      ),
                    ],
                  ),
                  loading: () => const ListTile(
                    title: Text('Informações do dispositivo'),
                    subtitle: Text('Carregando...'),
                  ),
                  error: (_, _) => const ListTile(
                    title: Text('Informações do dispositivo'),
                    subtitle: Text('Não disponíveis.'),
                  ),
                ),
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label:
                      'Identificador do dispositivo, ${_maskedDeviceId(widget.deviceId)}',
                  hint: 'Toque para exibir o identificador completo',
                  child: ListTile(
                    minVerticalPadding: 12,
                    title: const Text('Identificador do dispositivo'),
                    subtitle: Text(_maskedDeviceId(widget.deviceId)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showDeviceIdentifier,
                  ),
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

class _AdvancedCard extends ConsumerWidget {
  const _AdvancedCard({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  Future<bool> _confirmReset(BuildContext context, String title, String body) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
    return confirmed == true;
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
          title: Text('Redefinir preferências de alertas', style: TextStyle(color: errorColor)),
          subtitle: const Text('Restaura os padrões remotos; não altera porta ou hardware.'),
          onTap: () async {
            if (await _confirmReset(context, 'Redefinir preferências de alertas?', 'Os padrões serão salvos no servidor para "$deviceName".')) {
              await ref.read(deviceNotificationPreferencesProvider(deviceId).notifier).resetRemote();
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.settings_backup_restore, color: errorColor),
          title: Text('Redefinir preferências locais', style: TextStyle(color: errorColor)),
          subtitle: const Text('Restaura somente confirmação e autenticação da porta.'),
          onTap: () async {
            if (await _confirmReset(context, 'Redefinir preferências locais?', 'Somente as preferências locais da porta serão restauradas.')) {
              await ref.read(deviceSettingsProvider(deviceId).notifier).reset();
            }
          },
        ),
      ],
    );
  }
}
