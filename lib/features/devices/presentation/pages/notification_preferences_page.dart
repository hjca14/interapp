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
  const NotificationPreferencesPage({super.key, required this.deviceId});

  final String deviceId;

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
        title: const Text('Restaurar configurações padrão?'),
        content: const Text(
          'As preferências de alertas e horários voltarão aos valores padrão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
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

  /// Autosave failure is the only case that gets visible feedback (per
  /// [NotificationPreferencesState.phase] entering `saveError`/`conflict`).
  /// Gated on the *transition*, not the phase itself, so re-rendering while
  /// already showing an error — or while already synced — never stacks a
  /// second SnackBar for the same failure. A later edit or successful save
  /// moves the phase away from these two, which hides it again; success
  /// itself stays silent, matching autosave everywhere else in this screen.
  void _showSaveFailureIfNeeded(
    BuildContext context,
    NotificationPreferencesState? previous,
    NotificationPreferencesState next,
  ) {
    bool isSaveFailure(NotificationPreferencesState? value) =>
        value != null &&
        (value.phase == NotificationPreferencesPhase.saveError ||
            value.phase == NotificationPreferencesPhase.conflict);

    final wasFailing = isSaveFailure(previous);
    final isFailing = isSaveFailure(next);
    if (wasFailing == isFailing) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!isFailing) return;

    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: Text(
          next.message ?? 'Não foi possível salvar suas preferências.',
        ),
        action: SnackBarAction(
          label: 'Tentar novamente',
          // Always resends whatever `state.draft` currently holds — never a
          // snapshot of the draft that failed — since `retry()` reads
          // current state at call time, same as every other flush path.
          onPressed: _controller.retry,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      deviceNotificationPreferencesProvider(widget.deviceId),
    );
    final controller = ref.read(
      deviceNotificationPreferencesProvider(widget.deviceId).notifier,
    );

    ref.listen<NotificationPreferencesState>(
      deviceNotificationPreferencesProvider(widget.deviceId),
      (previous, next) => _showSaveFailureIfNeeded(context, previous, next),
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

/// The three states the user is offered — mutually exclusive on purpose (see
/// [_AlertsCard]'s doc comment on why the old two independent switches were
/// replaced). Distinct from [AlertMode]: this is only a UI-facing choice,
/// mapped to/from the wire enum by [_fromAlertMode]/[_toAlertMode].
enum _ExclusiveAlertChoice { call, notification, off }

_ExclusiveAlertChoice _fromAlertMode(AlertMode mode) => switch (mode) {
  // RING_AND_NOTIFICATION is a legacy value this app no longer writes (see
  // AlertMode's doc comment) but must still read/display correctly: from
  // the user's perspective it behaves exactly like "Chamada" (ringing
  // already includes the notification), so it is shown selected as such.
  AlertMode.ringOnly ||
  AlertMode.ringAndNotification => _ExclusiveAlertChoice.call,
  AlertMode.notificationOnly => _ExclusiveAlertChoice.notification,
  AlertMode.none => _ExclusiveAlertChoice.off,
};

AlertMode _toAlertMode(_ExclusiveAlertChoice choice) => switch (choice) {
  // Never RING_AND_NOTIFICATION: once the user actively picks a choice here
  // — including re-picking "Chamada" starting from a legacy value — this
  // app writes only NONE/RING_ONLY/NOTIFICATION_ONLY going forward.
  _ExclusiveAlertChoice.call => AlertMode.ringOnly,
  _ExclusiveAlertChoice.notification => AlertMode.notificationOnly,
  _ExclusiveAlertChoice.off => AlertMode.none,
};

/// Exclusive by design: a call and a plain notification are two different
/// experiences (one is a live, answerable/dismissable ringing event; the
/// other names something that already happened — see
/// `IncomingCallNotificationService`'s "Modo Chamada"/"Modo Notificação"
/// doc comments), so "get both at once" is no longer offered as a
/// combination of independent toggles.
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
    final selected = _fromAlertMode(preferences.alertMode);

    void change(_ExclusiveAlertChoice choice) {
      onChanged(preferences.copyWith(alertMode: _toAlertMode(choice)));
    }

    return SettingsSection(
      icon: Icons.notifications_outlined,
      title: 'Alertas',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) => _AlertModeSelector(
              selected: selected,
              enabled: enabled,
              onChanged: change,
              maxWidth: constraints.maxWidth,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(switch (selected) {
            _ExclusiveAlertChoice.call =>
              'Mostra a tela de chamada quando o interfone tocar.',
            _ExclusiveAlertChoice.notification =>
              'Mostra uma notificação sonora quando o interfone tocar, sem '
                  'abrir a tela de chamada.',
            _ExclusiveAlertChoice.off =>
              'Nenhum aviso é mostrado quando o interfone tocar.',
          }),
        ),
      ],
    );
  }
}

/// One alert-mode choice: [value] is the wire-facing selection, [fullLabel]/
/// [compactLabel] are the two label lengths [_AlertModeSelector] tries in
/// order, and [icon] is only ever shown alongside [fullLabel].
typedef _AlertModeOption = ({
  _ExclusiveAlertChoice value,
  String fullLabel,
  String compactLabel,
  IconData icon,
});

const _alertModeOptions = <_AlertModeOption>[
  (
    value: _ExclusiveAlertChoice.call,
    fullLabel: 'Chamada',
    compactLabel: 'Chamada',
    icon: Icons.call,
  ),
  (
    value: _ExclusiveAlertChoice.notification,
    fullLabel: 'Notificação',
    compactLabel: 'Aviso',
    icon: Icons.notifications,
  ),
  (
    value: _ExclusiveAlertChoice.off,
    fullLabel: 'Desativado',
    compactLabel: 'Desativado',
    icon: Icons.notifications_off,
  ),
];

/// Picks, then renders, one of three layouts for the exclusive alert-mode
/// choice — never lets a label wrap mid-word, overflow, or get truncated:
///
/// 1. A [SegmentedButton] with icons and full labels ("Chamada",
///    "Notificação", "Desativado"), if that measurably fits [maxWidth].
/// 2. A [SegmentedButton] with compact, icon-less labels ("Chamada",
///    "Aviso", "Desativado"), if that fits instead.
/// 3. A vertical, one-choice-per-row list ([RadioListTile]) otherwise — each
///    row gets the full available width, so a label can never fail to fit.
///
/// "Fits" is measured with a real [TextPainter] against the current
/// [MediaQuery] text scale, not a fixed device-width breakpoint: a normal
/// phone width at an accessible text scale (e.g. 1.3+) falls back to the
/// vertical layout exactly like a narrow width would, and a tablet-width
/// screen at a huge text scale does too — the decision follows actual
/// rendered content size, never a guess.
class _AlertModeSelector extends StatelessWidget {
  const _AlertModeSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.maxWidth,
  });

  final _ExclusiveAlertChoice selected;
  final bool enabled;
  final ValueChanged<_ExclusiveAlertChoice> onChanged;
  final double maxWidth;

  /// Approximate horizontal chrome (icon + gaps + button padding + border)
  /// `SegmentedButton` adds around each segment's label, in logical pixels.
  /// A deliberately generous estimate — this only has to decide *which*
  /// layout to use, never has to match Material's segmented-button layout
  /// algorithm exactly, and overestimating just means falling back to a
  /// smaller/vertical layout slightly earlier than the true limit, never
  /// picking a layout that actually overflows.
  static const _chromeWithIcon = 72.0;
  static const _chromeTextOnly = 40.0;

  bool _fits(BuildContext context, {required bool withIcons}) {
    final textScaler = MediaQuery.textScalerOf(context);
    final style =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    final chrome = withIcons ? _chromeWithIcon : _chromeTextOnly;
    var total = 0.0;
    for (final option in _alertModeOptions) {
      final label = withIcons ? option.fullLabel : option.compactLabel;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      total += painter.width + chrome;
    }
    return total <= maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (_fits(context, withIcons: true)) {
      return _segmentedButton(withIcons: true);
    }
    if (_fits(context, withIcons: false)) {
      return _segmentedButton(withIcons: false);
    }
    return _verticalChoices();
  }

  Widget _segmentedButton({required bool withIcons}) {
    return SegmentedButton<_ExclusiveAlertChoice>(
      segments: [
        for (final option in _alertModeOptions)
          ButtonSegment(
            value: option.value,
            label: Text(withIcons ? option.fullLabel : option.compactLabel),
            icon: withIcons ? Icon(option.icon) : null,
          ),
      ],
      selected: {selected},
      onSelectionChanged: enabled ? (value) => onChanged(value.first) : null,
    );
  }

  Widget _verticalChoices() {
    return RadioGroup<_ExclusiveAlertChoice>(
      groupValue: selected,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in _alertModeOptions)
            RadioListTile<_ExclusiveAlertChoice>(
              contentPadding: EdgeInsets.zero,
              title: Text(option.fullLabel),
              secondary: Icon(option.icon),
              value: option.value,
              enabled: enabled,
            ),
        ],
      ),
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
      title: 'Horários de silêncio',
      children: [
        SwitchListTile(
          title: const Text('Ativar horários de silêncio'),
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
