import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/device_status_presentation.dart';
import 'package:interapp/features/devices/presentation/pages/notification_preferences_page.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_refresh_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_settings_provider.dart';
import 'package:interapp/features/devices/presentation/widgets/settings_section.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

enum DeviceSettingsSection { main, firmware, diagnostics }

class DeviceSettingsPage extends ConsumerWidget {
  const DeviceSettingsPage({
    super.key,
    required this.deviceId,
    this.knownName,
    this.initialSection = DeviceSettingsSection.main,
  });

  final String deviceId;

  /// A name already known from elsewhere (typically `knownDeviceName` /
  /// `apiDevicesProvider`) — used only as an interim hint for the AppBar
  /// title while [apiDeviceDetailProvider] is still loading. Never frozen or
  /// treated as authoritative: this page watches that provider itself, so
  /// once the confirmed detail arrives it always wins. See
  /// [resolveKnownDeviceName].
  final String? knownName;
  final DeviceSettingsSection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSection == DeviceSettingsSection.firmware) {
      return FirmwarePage(deviceId: deviceId);
    }
    if (initialSection == DeviceSettingsSection.diagnostics) {
      return DiagnosticsPage(deviceId: deviceId);
    }

    final detail = ref.watch(apiDeviceDetailProvider(deviceId));
    final resolvedName = resolveKnownDeviceName(
      detailLoaded: detail.hasValue,
      confirmedDisplayName: detail.value?.displayName,
      knownName: knownName,
    );
    final local = ref.watch(deviceSettingsProvider(deviceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          resolvedName == null
              ? 'Configurações'
              : 'Configurações de $resolvedName',
        ),
      ),
      body: local.when(
        data: (settings) =>
            _DeviceSettingsBody(deviceId: deviceId, settings: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não foi possível carregar as preferências locais.'),
        ),
      ),
    );
  }
}

class _DeviceSettingsBody extends ConsumerWidget {
  const _DeviceSettingsBody({required this.deviceId, required this.settings});

  final String deviceId;
  final DeviceSettings settings;

  void _apply(WidgetRef ref, DeviceSettings Function(DeviceSettings) update) {
    ref.read(deviceSettingsProvider(deviceId).notifier).updateSettings(update);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NotificationsEntry(deviceId: deviceId),
        const SizedBox(height: 16),
        _DoorCard(
          settings: settings,
          onEnabledChanged: (value) => _apply(
            ref,
            (settings) => settings.copyWith(doorOpeningEnabled: value),
          ),
          onConfirmChanged: (value) => _apply(
            ref,
            (settings) => settings.copyWith(confirmBeforeOpeningDoor: value),
          ),
          onAuthChanged: (value) => _apply(
            ref,
            (settings) => settings.copyWith(
              requireDeviceAuthenticationToOpenDoor: value,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _AccessCard(detail: ref.watch(apiDeviceDetailProvider(deviceId))),
        const SizedBox(height: 16),
        _DeviceCard(deviceId: deviceId),
        const SizedBox(height: 16),
        _AdvancedCard(deviceId: deviceId),
      ],
    );
  }
}

/// Single navigable entry point to [NotificationPreferencesPage] — the
/// remote alert/quiet-schedule preferences never load or render on the main
/// settings screen, only a static summary, so opening this page is the only
/// thing that triggers their GET.
class _NotificationsEntry extends StatelessWidget {
  const _NotificationsEntry({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          Icons.notifications_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Notificações'),
        subtitle: const Text('Ligação, notificações e horários'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NotificationPreferencesPage(deviceId: deviceId),
          ),
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.detail});

  final AsyncValue<ApiDeviceDetail> detail;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.group_outlined,
      title: 'Acesso e compartilhamento',
      children: [
        detail.when(
          data: (device) => ListTile(
            title: const Text('Seu papel'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friendlyDeviceRole(device.role)),
                const SizedBox(height: 4),
                Text(_sharingPermissionDescription(device.role)),
              ],
            ),
            isThreeLine: true,
          ),
          loading: () => const ListTile(
            title: Text('Seu papel'),
            subtitle: Text('Carregando informações de acesso...'),
          ),
          error: (_, _) => const ListTile(
            title: Text('Seu papel'),
            subtitle: Text('Informações de acesso indisponíveis.'),
          ),
        ),
      ],
    );
  }
}

String _sharingPermissionDescription(DeviceRole role) => switch (role) {
  DeviceRole.owner || DeviceRole.admin =>
    'Você tem permissão para gerenciar o compartilhamento. Esse recurso ainda '
        'não está disponível.',
  DeviceRole.member =>
    'Você não tem permissão para compartilhar este dispositivo.',
};

/// Local opt-in followed by the existing confirmation/authentication policy.
/// Turning the opt-in off only collapses the two policy controls; their
/// values remain persisted for a later opt-in.
class _DoorCard extends StatelessWidget {
  const _DoorCard({
    required this.settings,
    required this.onEnabledChanged,
    required this.onConfirmChanged,
    required this.onAuthChanged,
  });

  final DeviceSettings settings;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onConfirmChanged;
  final ValueChanged<bool> onAuthChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.meeting_room_outlined,
      title: 'Porta',
      children: [
        SwitchListTile(
          title: const Text('Ativar abertura de porta'),
          subtitle: const Text(
            'Exibe a ação de abertura da porta neste dispositivo.',
          ),
          value: settings.doorOpeningEnabled,
          onChanged: onEnabledChanged,
        ),
        if (settings.doorOpeningEnabled) ...[
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
    return SettingsSection(
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
  const _AdvancedCard({required this.deviceId});

  final String deviceId;

  Future<bool> _confirmReset(
    BuildContext context,
    String title,
    String body,
  ) async {
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
    return SettingsSection(
      icon: Icons.warning_amber_outlined,
      title: 'Avançado',
      children: [
        ListTile(
          leading: Icon(Icons.settings_backup_restore, color: errorColor),
          title: Text(
            'Redefinir preferências locais',
            style: TextStyle(color: errorColor),
          ),
          subtitle: const Text(
            'Restaura somente confirmação e autenticação da porta.',
          ),
          onTap: () async {
            if (await _confirmReset(
              context,
              'Redefinir preferências locais?',
              'Somente as preferências locais da porta serão restauradas.',
            )) {
              await ref.read(deviceSettingsProvider(deviceId).notifier).reset();
            }
          },
        ),
      ],
    );
  }
}
