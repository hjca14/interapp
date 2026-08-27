import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';
import 'package:interapp/features/devices/presentation/widgets/settings_section.dart';

/// Dedicated "Notificações" screen. Everything here autosaves: there is no
/// Save button, no discard dialog, and no way to lose an edit by navigating
/// away — [DeviceNotificationPreferencesController] outlives this page and
/// keeps syncing after it is popped.
class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  // `ref.read` throws once this widget is being unmounted — Riverpod
  // requires a still-valid BuildContext — so the controller reference is
  // captured up front in `initState` (via the eager read below) and reused
  // in `dispose`, instead of calling `ref.read` there directly.
  late final DeviceNotificationPreferencesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(
      deviceNotificationPreferencesProvider(widget.deviceId).notifier,
    );
  }

  @override
  void dispose() {
    // Best-effort only: shrinks the window between an edit and the outbox
    // write that protects it against the app being killed. Correctness
    // never depends on this running — the debounce timer covers it anyway.
    // Deferred to a microtask: Riverpod forbids synchronously mutating a
    // provider's state from within a widget's `dispose()`, since that runs
    // as part of the current frame's build/unmount pass.
    final controller = _controller;
    scheduleMicrotask(controller.flushPendingNow);
    super.dispose();
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redefinir preferências de alertas?'),
        content: Text(
          'Os padrões serão salvos no servidor para "${widget.deviceName}".',
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
    if (confirmed == true && context.mounted) {
      await ref
          .read(deviceNotificationPreferencesProvider(widget.deviceId).notifier)
          .resetRemote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      deviceNotificationPreferencesProvider(widget.deviceId),
    );
    final controller = ref.read(
      deviceNotificationPreferencesProvider(widget.deviceId).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (state.canReset)
            IconButton(
              tooltip: 'Restaurar padrões',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => _confirmReset(context),
            ),
        ],
      ),
      body: switch (state.phase) {
        NotificationPreferencesPhase.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        NotificationPreferencesPhase.loadError => _LoadErrorView(
          message: state.message,
          onRetry: controller.retry,
        ),
        NotificationPreferencesPhase.sessionExpired => const Center(
          child: CircularProgressIndicator(),
        ),
        _ => _NotificationPreferencesBody(state: state, controller: controller),
      },
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(
              message ??
                  'Não foi possível carregar as preferências de alertas.',
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
}

class _NotificationPreferencesBody extends StatelessWidget {
  const _NotificationPreferencesBody({
    required this.state,
    required this.controller,
  });

  final NotificationPreferencesState state;
  final DeviceNotificationPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft;
    if (draft == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final enabled = state.canEdit;
    final resolving =
        state.phase == NotificationPreferencesPhase.resolvingTimezone;

    void edit(DeviceNotificationPreferences value) {
      controller.edit((_) => value);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SyncStatus(state: state, onRetry: controller.retry),
        const SizedBox(height: 8),
        _AlertsCard(preferences: draft, enabled: enabled, onChanged: edit),
        const SizedBox(height: 16),
        _QuietScheduleCard(
          schedule: draft.quietSchedule,
          enabled: enabled,
          resolvingTimezone: resolving,
          timezoneError: state.timezoneError,
          onEnabled: controller.enableSchedule,
          onChanged: (schedule) =>
              edit(draft.copyWith(quietSchedule: schedule)),
        ),
      ],
    );
  }
}

/// Small, stable, discreet feedback replacing the old Save button: no
/// SnackBars on every change, just "Salvando..." while anything is
/// unconverged and "Tudo salvo" once baseline and draft match with nothing
/// pending — see [NotificationPreferencesState.isSyncing].
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.state, required this.onRetry});

  final NotificationPreferencesState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (state.phase == NotificationPreferencesPhase.saveError ||
        state.phase == NotificationPreferencesPhase.conflict) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: errorColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.message ?? 'Não foi possível sincronizar.',
                  style: TextStyle(color: errorColor),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.isSyncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Salvando...'),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18),
          SizedBox(width: 8),
          Text('Tudo salvo'),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({
    required this.preferences,
    required this.enabled,
    required this.onChanged,
  });

  final DeviceNotificationPreferences preferences;
  final bool enabled;
  final ValueChanged<DeviceNotificationPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    final mode = preferences.alertMode;

    void change({bool? ring, bool? notification}) {
      onChanged(
        preferences.copyWith(
          alertMode: AlertMode.from(
            ring: ring ?? mode.includesRing,
            notification: notification ?? mode.includesNotification,
          ),
        ),
      );
    }

    return SettingsSection(
      icon: Icons.notifications_outlined,
      title: 'Alertas',
      children: [
        SwitchListTile(
          title: const Text('Receber ligação'),
          subtitle: const Text(
            'Mostra a tela de chamada quando o interfone tocar.',
          ),
          value: mode.includesRing,
          onChanged: enabled ? (value) => change(ring: value) : null,
        ),
        SwitchListTile(
          title: const Text('Receber notificação'),
          subtitle: const Text(
            'Mostra uma notificação relacionada ao toque do interfone.',
          ),
          value: mode.includesNotification,
          onChanged: enabled ? (value) => change(notification: value) : null,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'As preferências já ficam salvas. Elas passarão a controlar os '
            'alertas quando a integração de notificações for ativada.',
          ),
        ),
      ],
    );
  }
}

const _weekdayLabels = {
  1: 'Seg',
  2: 'Ter',
  3: 'Qua',
  4: 'Qui',
  5: 'Sex',
  6: 'Sáb',
  7: 'Dom',
};

class _QuietScheduleCard extends StatelessWidget {
  const _QuietScheduleCard({
    required this.schedule,
    required this.enabled,
    required this.resolvingTimezone,
    required this.timezoneError,
    required this.onEnabled,
    required this.onChanged,
  });

  final QuietSchedule schedule;
  final bool enabled;
  final bool resolvingTimezone;
  final String? timezoneError;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<QuietSchedule> onChanged;

  Future<void> _pick(BuildContext context, bool start) async {
    final value = start ? schedule.startTime : schedule.endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: value?.hour ?? (start ? 22 : 7),
        minute: value?.minute ?? 0,
      ),
    );
    if (picked == null) return;
    final time = ClockTime(hour: picked.hour, minute: picked.minute);
    onChanged(
      start
          ? schedule.copyWith(startTime: time)
          : schedule.copyWith(endTime: time),
    );
  }

  void _toggleDay(int day) {
    final days = Set<int>.from(schedule.days);
    if (!days.remove(day)) days.add(day);
    onChanged(schedule.copyWith(days: days));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.schedule,
      title: 'Horários sem ligação',
      children: [
        SwitchListTile(
          title: const Text('Ativar horários sem ligação'),
          value: schedule.enabled,
          onChanged: enabled ? onEnabled : null,
          secondary: resolvingTimezone
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        if (timezoneError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              timezoneError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (schedule.enabled) ...[
          ListTile(
            title: const Text('Horário'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: enabled ? () => _pick(context, true) : null,
                  child: Text(schedule.startTime?.wireValue ?? '--:--'),
                ),
                const Text('—'),
                TextButton(
                  onPressed: enabled ? () => _pick(context, false) : null,
                  child: Text(schedule.endTime?.wireValue ?? '--:--'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              children: _weekdayLabels.entries.map((day) {
                return FilterChip(
                  label: Text(day.value),
                  selected: schedule.days.contains(day.key),
                  onSelected: enabled ? (_) => _toggleDay(day.key) : null,
                );
              }).toList(),
            ),
          ),
          ListTile(
            title: const Text('Fuso horário'),
            subtitle: Text(schedule.timezone ?? 'Indisponível'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<QuietScheduleBehavior>(
              segments: const [
                ButtonSegment(
                  value: QuietScheduleBehavior.notificationOnly,
                  label: Text('Só notificação'),
                ),
                ButtonSegment(
                  value: QuietScheduleBehavior.blockAll,
                  label: Text('Bloquear tudo'),
                ),
              ],
              selected: {schedule.behavior},
              onSelectionChanged: enabled
                  ? (value) =>
                        onChanged(schedule.copyWith(behavior: value.first))
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              schedule.behavior == QuietScheduleBehavior.notificationOnly
                  ? 'Durante esse horário, o celular não tocará como ligação. '
                        'A notificação continua disponível se estiver ativada '
                        'em Alertas.'
                  : 'Durante esse horário, ligações e notificações desse '
                        'InterBridge não serão exibidas.',
            ),
          ),
        ],
      ],
    );
  }
}
