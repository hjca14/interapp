import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/device_status_presentation.dart';
import 'package:interapp/features/devices/presentation/pages/api_device_detail_page.dart';
import 'package:interapp/features/devices/presentation/pages/edit_device_name_page.dart';
import 'package:interapp/features/devices/presentation/pages/notification_preferences_page.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_refresh_provider.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/devices/presentation/widgets/door_command_card.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/commands/data/command_repository.dart';
import 'package:interapp/features/commands/domain/command_models.dart';
import 'package:interapp/features/commands/presentation/providers/door_command_provider.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:interapp/features/auth/presentation/providers/biometric_lock_providers.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';

class _MemoryFavoritesRepository extends LocalFavoritesRepository {
  _MemoryFavoritesRepository(this.values);
  final List<Favorite> values;

  @override
  Future<List<Favorite>> getAll(String deviceId) async => values;

  @override
  Future<void> saveAll(String deviceId, List<Favorite> favorites) async {}
}

class _SettingsRepository implements DeviceSettingsRepository {
  _SettingsRepository(this.result);
  final Future<DeviceSettings> result;

  @override
  Future<DeviceSettings> get(String deviceId) => result;

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {}
}

/// Minimal fake so any test that reaches `DeviceSettingsPage` (its Alertas
/// section auto-loads via `deviceNotificationPreferencesProvider`) doesn't
/// hit the real, unoverridden `apiClientProvider`/`appConfigProvider` chain.
class _NotificationPreferencesRepository
    implements DeviceNotificationPreferencesRepository {
  DeviceNotificationPreferences value = DeviceNotificationPreferences();

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async => value;

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    value = draft;
    return value;
  }
}

class _ManualPollingScheduler implements StatusPollingScheduler {
  _ManualPollingHandle? handle;

  bool get hasActiveTimer => handle?.active == true;

  @override
  StatusPollingHandle periodic(Duration interval, void Function() callback) {
    handle?.cancel();
    return handle = _ManualPollingHandle(interval, callback);
  }

  void elapse(Duration duration) => handle?.elapse(duration);
}

class _ManualPollingHandle implements StatusPollingHandle {
  _ManualPollingHandle(this.interval, this.callback);
  final Duration interval;
  final void Function() callback;
  Duration elapsed = Duration.zero;
  bool active = true;

  void elapse(Duration duration) {
    if (!active) return;
    elapsed += duration;
    while (active && elapsed >= interval) {
      elapsed -= interval;
      callback();
    }
  }

  @override
  void cancel() => active = false;
}

class _Authenticator implements BiometricAuthenticator {
  _Authenticator({
    this.configuredAvailability = BiometricAvailability.available,
    this.result = BiometricAuthenticationResult.success,
    this.pendingResult,
  });

  final BiometricAvailability configuredAvailability;
  final BiometricAuthenticationResult result;
  final Future<BiometricAuthenticationResult>? pendingResult;
  int availabilityCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<BiometricAvailability> availability() async {
    availabilityCalls++;
    return configuredAvailability;
  }

  @override
  Future<BiometricAuthenticationResult> authenticate() {
    authenticateCalls++;
    return pendingResult ?? Future.value(result);
  }
}

/// Test double for [DeviceRepository]. Detail-page tests mostly exercise
/// `getDeviceDetails` (via [loadDetail]) and `updateDeviceName` (via
/// [onUpdateName]) — `listDevices` just backs the unrelated
/// `apiDevicesProvider` that also lives in the widget tree, so it returns an
/// empty page by default rather than modeling the list feature here too.
/// [listItems] lets the known-name-reuse tests seed that list with a summary
/// the detail page can read before its own GET resolves.
class _DeviceDirectory implements DeviceRepository {
  _DeviceDirectory({
    required this.role,
    this.loadDetail,
    this.onUpdateName,
    this.listItems = const [],
  });

  final DeviceRole role;
  final Future<ApiDeviceDetail> Function()? loadDetail;
  final Future<ApiDeviceDetail> Function(String deviceId, String? displayName)?
  onUpdateName;
  final List<ApiDeviceSummary> listItems;
  int updateNameCalls = 0;

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async {
    return ApiDevicePage(items: listItems);
  }

  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) {
    if (loadDetail != null) return loadDetail!();
    return Future.value(
      ApiDeviceDetail(
        deviceId: deviceId,
        displayName: 'Portaria',
        hardwareVersion: 'HW-2',
        ownershipStatus: 'claimed',
        provisioningStatus: 'active',
        role: role,
      ),
    );
  }

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) {
    updateNameCalls++;
    if (onUpdateName != null) return onUpdateName!(deviceId, displayName);
    return Future.value(
      ApiDeviceDetail(
        deviceId: deviceId,
        displayName: displayName,
        hardwareVersion: 'HW-2',
        ownershipStatus: 'claimed',
        provisioningStatus: 'active',
        role: role,
      ),
    );
  }
}

class _CommandRepository implements CommandRepository {
  _CommandRepository({
    this.commandStatus,
    this.createErrors = const [],
    this.createResponses = const [],
  });

  final Future<CommandStatus>? commandStatus;
  final List<ApiFailure> createErrors;
  final List<Future<AcceptedCommand>> createResponses;
  int createCalls = 0;
  int getCalls = 0;
  final List<String> idempotencyKeys = [];

  @override
  Future<AcceptedCommand> createOpenDoorCommand(
    DeviceId deviceId,
    String idempotencyKey,
  ) async {
    final call = createCalls++;
    idempotencyKeys.add(idempotencyKey);
    if (call < createErrors.length) throw createErrors[call];
    if (call < createResponses.length) return createResponses[call];
    expect(idempotencyKey, isNotEmpty);
    return AcceptedCommand(
      commandId: CommandId('0123456789abcdef0123456789abcdef'),
      issuedAt: UtcTimestamp.parse('2026-08-22T12:00:00Z'),
      expiresAt: UtcTimestamp.parse('2026-08-22T12:00:30Z'),
    );
  }

  @override
  Future<CommandStatus> getCommand(
    DeviceId deviceId,
    CommandId commandId,
  ) async {
    getCalls++;
    final pendingStatus = commandStatus;
    if (pendingStatus != null) return pendingStatus;
    return CommandStatus(
      commandId: commandId,
      state: CommandState.rejected,
      rejection: const CommandRejection('CAPABILITY_DISABLED'),
    );
  }
}

void main() {
  const deviceId = 'ib-00000000000000000000000000000001';

  Widget subject({
    List<Favorite> favorites = const [],
    DeviceRole role = DeviceRole.owner,
    CommandRepository? commands,
    Stream<AuthSession>? sessions,
    DoorCommandCooldownScheduler? cooldownScheduler,
    Future<DeviceSettings>? settings,
    BiometricAuthenticator? authenticator,
    StatusPollingScheduler? pollingScheduler,
    Future<ApiDeviceStatus> Function()? loadStatus,
    Future<ApiDeviceDetail> Function()? loadDetail,
    Future<ApiDeviceDetail> Function(String deviceId, String? displayName)?
    onUpdateName,
    List<ApiDeviceSummary> listItems = const [],
  }) {
    return ProviderScope(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(
          _DeviceDirectory(
            role: role,
            loadDetail: loadDetail,
            onUpdateName: onUpdateName,
            listItems: listItems,
          ),
        ),
        apiDeviceStatusProvider.overrideWith((ref, id) async {
          if (loadStatus != null) return loadStatus();
          return ApiDeviceStatus(
            deviceId: deviceId,
            connectivity: DeviceConnectivity.recentlySeen,
            freshness: DeviceFreshness.fresh,
            health: ApiDeviceHealth(
              intercomState: IntercomState.idle,
              firmwareVersion: '2.0.1',
              lastSeenAt: DateTime.utc(2026, 8, 20, 12),
            ),
          );
        }),
        favoritesRepositoryProvider.overrideWithValue(
          _MemoryFavoritesRepository(favorites),
        ),
        deviceSettingsRepositoryProvider.overrideWithValue(
          _SettingsRepository(
            settings ??
                Future.value(const DeviceSettings(doorOpeningEnabled: true)),
          ),
        ),
        deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
          _NotificationPreferencesRepository(),
        ),
        doorDeviceAuthenticatorProvider.overrideWithValue(
          authenticator ?? _Authenticator(),
        ),
        authSessionProvider.overrideWith(
          (ref) =>
              sessions ?? Stream.value(const AuthSession(isSignedIn: true)),
        ),
        commandRepositoryProvider.overrideWithValue(
          commands ?? _CommandRepository(),
        ),
        if (cooldownScheduler != null)
          doorCommandCooldownSchedulerProvider.overrideWithValue(
            cooldownScheduler,
          ),
        if (pollingScheduler != null)
          statusPollingSchedulerProvider.overrideWithValue(pollingScheduler),
      ],
      child: MaterialApp(
        navigatorObservers: [deviceDetailRouteObserver],
        home: const ApiDeviceDetailPage(deviceId: deviceId),
      ),
    );
  }

  testWidgets('combines API summary with dialer and favorites navigation', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    expect(find.text('Resumo'), findsOneWidget);
    expect(find.text('Discar'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(
      find.text(
        formatLastCommunication(DateTime.utc(2026, 8, 20, 12), DateTime.now()),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Online indica'), findsNothing);
    expect(find.textContaining('RECENTLYSEEN'), findsNothing);
    expect(find.textContaining('FRESH'), findsNothing);
    expect(find.textContaining('2.0.1'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('does not build the door action before local opt-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(settings: Future.value(const DeviceSettings())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DoorCommandCard), findsNothing);
    expect(find.text('Abrir porta'), findsNothing);
  });

  testWidgets('loads initially and polls exactly at 60 seconds', (
    tester,
  ) async {
    final scheduler = _ManualPollingScheduler();
    var statusCalls = 0;
    await tester.pumpWidget(
      subject(
        pollingScheduler: scheduler,
        loadStatus: () async {
          statusCalls++;
          return ApiDeviceStatus(
            deviceId: deviceId,
            connectivity: DeviceConnectivity.recentlySeen,
            freshness: DeviceFreshness.fresh,
            health: ApiDeviceHealth(
              intercomState: IntercomState.idle,
              firmwareVersion: '2.0.1',
              lastSeenAt: DateTime.utc(2026, 8, 23, 12),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(statusCalls, 1);

    scheduler.elapse(const Duration(seconds: 59));
    await tester.pump();
    expect(statusCalls, 1);

    scheduler.elapse(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(statusCalls, 2);
  });

  testWidgets('coalesces concurrent polling refreshes', (tester) async {
    final scheduler = _ManualPollingScheduler();
    final pending = Completer<ApiDeviceStatus>();
    var statusCalls = 0;
    await tester.pumpWidget(
      subject(
        pollingScheduler: scheduler,
        loadStatus: () {
          statusCalls++;
          if (statusCalls == 1) {
            return Future.value(
              ApiDeviceStatus(
                deviceId: deviceId,
                connectivity: DeviceConnectivity.recentlySeen,
                freshness: DeviceFreshness.fresh,
              ),
            );
          }
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    scheduler.elapse(const Duration(seconds: 120));
    await tester.pump();
    expect(statusCalls, 2);
    pending.complete(
      ApiDeviceStatus(
        deviceId: deviceId,
        connectivity: DeviceConnectivity.recentlySeen,
        freshness: DeviceFreshness.fresh,
      ),
    );
    await tester.pumpAndSettle();
  });

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
  ]) {
    testWidgets('${state.name} suspends polling while in background', (
      tester,
    ) async {
      final scheduler = _ManualPollingScheduler();
      var statusCalls = 0;
      await tester.pumpWidget(
        subject(
          pollingScheduler: scheduler,
          loadStatus: () async {
            statusCalls++;
            return ApiDeviceStatus(
              deviceId: deviceId,
              connectivity: DeviceConnectivity.unknown,
              freshness: DeviceFreshness.unknown,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      scheduler.elapse(const Duration(minutes: 5));
      await tester.pump();
      expect(statusCalls, 1);
      expect(scheduler.hasActiveTimer, isFalse);
    });
  }

  testWidgets('resume refreshes once immediately and restarts cadence', (
    tester,
  ) async {
    final scheduler = _ManualPollingScheduler();
    var statusCalls = 0;
    await tester.pumpWidget(
      subject(
        pollingScheduler: scheduler,
        loadStatus: () async {
          statusCalls++;
          return ApiDeviceStatus(
            deviceId: deviceId,
            connectivity: DeviceConnectivity.unknown,
            freshness: DeviceFreshness.unknown,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(statusCalls, 2);
    scheduler.elapse(const Duration(seconds: 59));
    await tester.pump();
    expect(statusCalls, 2);
    scheduler.elapse(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(statusCalls, 3);
  });

  testWidgets('dispose and route coverage cancel polling', (tester) async {
    final scheduler = _ManualPollingScheduler();
    var statusCalls = 0;
    await tester.pumpWidget(
      subject(
        pollingScheduler: scheduler,
        loadStatus: () async {
          statusCalls++;
          return ApiDeviceStatus(
            deviceId: deviceId,
            connectivity: DeviceConnectivity.unknown,
            freshness: DeviceFreshness.unknown,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(scheduler.hasActiveTimer, isFalse);
    scheduler.elapse(const Duration(minutes: 5));
    expect(statusCalls, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(statusCalls, 2);
    expect(scheduler.hasActiveTimer, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(scheduler.hasActiveTimer, isFalse);
  });

  testWidgets('status card opens friendly diagnostics and firmware is honest', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(find.text('Diagnóstico'), findsOneWidget);
    expect(find.text('Estado do interfone'), findsOneWidget);
    expect(find.text('Versão do hardware'), findsOneWidget);
    expect(find.text('HW-2'), findsOneWidget);
    expect(find.text('Estado de configuração'), findsOneWidget);
    expect(find.text('Configurado'), findsOneWidget);
    expect(find.text('active'), findsNothing);
    expect(find.text('Em espera'), findsOneWidget);
    expect(
      find.text(formatDiagnosticTimestamp(DateTime.utc(2026, 8, 20, 12))),
      findsOneWidget,
    );
    expect(find.textContaining('.000'), findsNothing);
    expect(find.textContaining('RECENTLYSEEN'), findsNothing);
    expect(find.text('Discar'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(find.text('Configurações de Portaria'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Firmware'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Firmware'));
    await tester.pump();
    await tester.tap(find.text('Firmware'));
    await tester.pumpAndSettle();
    expect(find.text('2.0.1'), findsOneWidget);
    expect(find.text('Atualização OTA ainda não disponível'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Atualizar'), findsNothing);
  });

  testWidgets('pull-to-refresh waits for detail and status', (tester) async {
    final detailRefresh = Completer<ApiDeviceDetail>();
    final statusRefresh = Completer<ApiDeviceStatus>();
    var detailCalls = 0;
    var statusCalls = 0;
    ApiDeviceDetail detail() => ApiDeviceDetail(
      deviceId: deviceId,
      displayName: 'Portaria',
      ownershipStatus: 'claimed',
      provisioningStatus: 'active',
      role: DeviceRole.owner,
    );
    ApiDeviceStatus status() => ApiDeviceStatus(
      deviceId: deviceId,
      connectivity: DeviceConnectivity.recentlySeen,
      freshness: DeviceFreshness.fresh,
      health: ApiDeviceHealth(
        intercomState: IntercomState.idle,
        firmwareVersion: '2.0.1',
        lastSeenAt: DateTime.utc(2026, 8, 23, 12),
      ),
    );
    await tester.pumpWidget(
      subject(
        loadDetail: () {
          detailCalls++;
          return detailCalls == 1
              ? Future.value(detail())
              : detailRefresh.future;
        },
        loadStatus: () {
          statusCalls++;
          return statusCalls == 1
              ? Future.value(status())
              : statusRefresh.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    detailRefresh.complete(detail());
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    statusRefresh.complete(status());
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(detailCalls, 2);
    expect(statusCalls, 2);
  });

  testWidgets('refresh error preserves status and shows friendly feedback', (
    tester,
  ) async {
    var statusCalls = 0;
    await tester.pumpWidget(
      subject(
        loadStatus: () async {
          statusCalls++;
          if (statusCalls > 1) throw StateError('offline');
          return ApiDeviceStatus(
            deviceId: deviceId,
            connectivity: DeviceConnectivity.recentlySeen,
            freshness: DeviceFreshness.fresh,
            health: ApiDeviceHealth(
              intercomState: IntercomState.idle,
              firmwareVersion: '2.0.1',
              lastSeenAt: DateTime.utc(2026, 8, 23, 12),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
    expect(
      find.text('Não foi possível atualizar agora. Tente novamente.'),
      findsOneWidget,
    );
  });

  for (final role in [DeviceRole.admin, DeviceRole.member]) {
    testWidgets('${role.name.toUpperCase()} cannot send a command', (
      tester,
    ) async {
      final commands = _CommandRepository();
      final authenticator = _Authenticator();
      await tester.pumpWidget(
        subject(
          role: role,
          commands: commands,
          authenticator: authenticator,
          settings: Future.value(
            const DeviceSettings(
              doorOpeningEnabled: true,
              confirmBeforeOpeningDoor: false,
              requireDeviceAuthenticationToOpenDoor: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
            .onPressed,
        isNull,
      );
      expect(commands.createCalls, 0);
      expect(authenticator.authenticateCalls, 0);
    });
  }

  testWidgets('cancel sends no POST and confirmation sends exactly one', (
    tester,
  ) async {
    final commands = _CommandRepository();
    final authenticator = _Authenticator();
    await tester.pumpWidget(
      subject(
        commands: commands,
        authenticator: authenticator,
        settings: Future.value(
          const DeviceSettings(
            doorOpeningEnabled: true,
            confirmBeforeOpeningDoor: true,
            requireDeviceAuthenticationToOpenDoor: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    expect(find.text('Abrir porta?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(commands.createCalls, 0);
    expect(authenticator.authenticateCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    await tester.tap(find.text('Enviar solicitação'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(commands.createCalls, 1);
    expect(authenticator.authenticateCalls, 1);
    expect(
      find.textContaining('A abertura ainda não está configurada'),
      findsOneWidget,
    );
  });

  for (final confirm in [true, false]) {
    for (final requireAuthentication in [true, false]) {
      testWidgets(
        'door preferences confirm=$confirm auth=$requireAuthentication',
        (tester) async {
          final commands = _CommandRepository();
          final authenticator = _Authenticator();
          await tester.pumpWidget(
            subject(
              commands: commands,
              authenticator: authenticator,
              settings: Future.value(
                DeviceSettings(
                  doorOpeningEnabled: true,
                  confirmBeforeOpeningDoor: confirm,
                  requireDeviceAuthenticationToOpenDoor: requireAuthentication,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
          await tester.pump();
          expect(
            find.text('Abrir porta?'),
            confirm ? findsOneWidget : findsNothing,
          );
          expect(
            authenticator.authenticateCalls,
            !confirm && requireAuthentication ? 1 : 0,
          );
          if (confirm) {
            await tester.tap(find.text('Enviar solicitação'));
            await tester.pump();
          }
          await tester.pump();

          expect(
            authenticator.authenticateCalls,
            requireAuthentication ? 1 : 0,
          );
          expect(commands.createCalls, 1);
        },
      );
    }
  }

  testWidgets('no POST occurs before device authentication succeeds', (
    tester,
  ) async {
    final authentication = Completer<BiometricAuthenticationResult>();
    final authenticator = _Authenticator(pendingResult: authentication.future);
    final commands = _CommandRepository();
    await tester.pumpWidget(
      subject(
        commands: commands,
        authenticator: authenticator,
        settings: Future.value(
          const DeviceSettings(
            doorOpeningEnabled: true,
            confirmBeforeOpeningDoor: true,
            requireDeviceAuthenticationToOpenDoor: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    expect(authenticator.authenticateCalls, 0);
    await tester.tap(find.text('Enviar solicitação'));
    await tester.pump();
    expect(authenticator.authenticateCalls, 1);
    expect(commands.createCalls, 0);

    authentication.complete(BiometricAuthenticationResult.success);
    await tester.pump();
    await tester.pump();
    expect(commands.createCalls, 1);
  });

  for (final result in [
    BiometricAuthenticationResult.canceled,
    BiometricAuthenticationResult.temporarilyLocked,
    BiometricAuthenticationResult.failed,
  ]) {
    testWidgets('authentication ${result.name} prevents POST', (tester) async {
      final commands = _CommandRepository();
      await tester.pumpWidget(
        subject(
          commands: commands,
          authenticator: _Authenticator(result: result),
          settings: Future.value(
            const DeviceSettings(
              doorOpeningEnabled: true,
              confirmBeforeOpeningDoor: false,
              requireDeviceAuthenticationToOpenDoor: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
      await tester.pump();
      await tester.pump();
      expect(commands.createCalls, 0);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets('unavailable device authentication prevents POST', (
    tester,
  ) async {
    final commands = _CommandRepository();
    final authenticator = _Authenticator(
      configuredAvailability: BiometricAvailability.unsupported,
    );
    await tester.pumpWidget(
      subject(
        commands: commands,
        authenticator: authenticator,
        settings: Future.value(
          const DeviceSettings(
            doorOpeningEnabled: true,
            confirmBeforeOpeningDoor: false,
            requireDeviceAuthenticationToOpenDoor: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    expect(authenticator.authenticateCalls, 0);
    expect(commands.createCalls, 0);
    expect(
      find.text('Autenticação segura do aparelho indisponível.'),
      findsOneWidget,
    );
  });

  testWidgets('double tap before POST still creates one command', (
    tester,
  ) async {
    final commands = _CommandRepository();
    await tester.pumpWidget(
      subject(
        commands: commands,
        settings: Future.value(
          const DeviceSettings(
            doorOpeningEnabled: true,
            confirmBeforeOpeningDoor: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = find.widgetWithText(FilledButton, 'Abrir');
    await tester.tap(open);
    await tester.tap(open, warnIfMissed: false);
    expect(commands.createCalls, 1);
  });

  testWidgets('lifecycle dismisses confirmation without POST', (tester) async {
    final commands = _CommandRepository();
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    expect(find.text('Abrir porta?'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Abrir porta?'), findsNothing);
    expect(commands.createCalls, 0);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('native authentication lifecycle preserves approved action', (
    tester,
  ) async {
    final authentication = Completer<BiometricAuthenticationResult>();
    final commands = _CommandRepository();
    await tester.pumpWidget(
      subject(
        commands: commands,
        authenticator: _Authenticator(pendingResult: authentication.future),
        settings: Future.value(
          const DeviceSettings(
            doorOpeningEnabled: true,
            confirmBeforeOpeningDoor: false,
            requireDeviceAuthenticationToOpenDoor: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pump();
    expect(commands.createCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(commands.createCalls, 0);
    authentication.complete(BiometricAuthenticationResult.success);
    await tester.pump();
    expect(commands.createCalls, 1);
  });

  for (final result in [
    BiometricAuthenticationResult.canceled,
    BiometricAuthenticationResult.failed,
  ]) {
    testWidgets('authentication $result after lifecycle does not POST', (
      tester,
    ) async {
      final authentication = Completer<BiometricAuthenticationResult>();
      final commands = _CommandRepository();
      await tester.pumpWidget(
        subject(
          commands: commands,
          authenticator: _Authenticator(pendingResult: authentication.future),
          settings: Future.value(
            const DeviceSettings(
              doorOpeningEnabled: true,
              confirmBeforeOpeningDoor: false,
              requireDeviceAuthenticationToOpenDoor: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(commands.createCalls, 0);

      authentication.complete(result);
      await tester.pump();
      expect(commands.createCalls, 0);
    });
  }

  testWidgets('loading and failed preferences keep door action disabled', (
    tester,
  ) async {
    final pending = Completer<DeviceSettings>();
    final commands = _CommandRepository();
    await tester.pumpWidget(
      subject(commands: commands, settings: pending.future),
    );
    await tester.pump();
    expect(find.byType(DoorCommandCard), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    final failed = Completer<DeviceSettings>();
    await tester.pumpWidget(
      subject(commands: commands, settings: failed.future),
    );
    await tester.pump();
    failed.completeError(StateError('safe fake'));
    await tester.pump();
    expect(find.byType(DoorCommandCard), findsNothing);
    expect(commands.createCalls, 0);
  });

  testWidgets('retry button honors cooldown without a real timer', (
    tester,
  ) async {
    final cooldown = _ManualCooldownScheduler();
    final commands = _CommandRepository(
      createErrors: [
        const ApiFailure(
          ApiFailureKind.timeout,
          'timeout',
          retryAfter: Duration(seconds: 5),
        ),
      ],
    );
    await tester.pumpWidget(
      subject(commands: commands, cooldownScheduler: cooldown),
    );
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);
    await tester.pump();

    final retry = find.widgetWithText(FilledButton, 'Tentar novamente');
    expect(tester.widget<FilledButton>(retry).onPressed, isNull);
    expect(commands.createCalls, 1);

    cooldown.elapse();
    await tester.pump();
    expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
    await tester.tap(retry);
    expect(commands.createCalls, 2);
  });

  testWidgets('resume enables a new explicit action with a new key', (
    tester,
  ) async {
    final commands = _CommandRepository(
      commandStatus: Completer<CommandStatus>().future,
    );
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);
    expect(commands.createCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Solicitação interrompida.'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(commands.createCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );

    await _confirmDoorCommand(tester);
    expect(commands.createCalls, 2);
    expect(commands.idempotencyKeys, hasLength(2));
    expect(commands.idempotencyKeys[1], isNot(commands.idempotencyKeys[0]));
  });

  testWidgets('late pre-pause POST cannot affect resumed controller', (
    tester,
  ) async {
    final oldPost = Completer<AcceptedCommand>();
    final commands = _CommandRepository(createResponses: [oldPost.future]);
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);
    expect(find.text('Enviando solicitação…'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Solicitação interrompida.'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(commands.createCalls, 1);
    expect(commands.getCalls, 0);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );

    oldPost.complete(
      AcceptedCommand(
        commandId: CommandId('fedcba9876543210fedcba9876543210'),
        issuedAt: UtcTimestamp.parse('2026-08-22T12:01:00Z'),
        expiresAt: UtcTimestamp.parse('2026-08-22T12:01:30Z'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(commands.getCalls, 0);
    expect(find.text('Enviando solicitação…'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );

    await _confirmDoorCommand(tester);
    expect(commands.createCalls, 2);
    expect(commands.idempotencyKeys, hasLength(2));
    expect(commands.idempotencyKeys[1], isNot(commands.idempotencyKeys[0]));
  });

  testWidgets('navigation and logout cancel polling silently', (tester) async {
    final sessions = StreamController<AuthSession>();
    addTearDown(sessions.close);
    final commands = _CommandRepository(
      commandStatus: Completer<CommandStatus>().future,
    );
    await tester.pumpWidget(
      subject(commands: commands, sessions: sessions.stream),
    );
    sessions.add(const AuthSession(isSignedIn: true));
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);

    sessions.add(const AuthSession.signedOut());
    await tester.pump();
    expect(find.text('Solicitação interrompida.'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(commands.createCalls, 1);
  });

  testWidgets('navigation disposes active polling without an error', (
    tester,
  ) async {
    final commands = _CommandRepository(
      commandStatus: Completer<CommandStatus>().future,
    );
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(commands.createCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recreated page requires a new explicit action', (tester) async {
    final commands = _CommandRepository(
      commandStatus: Completer<CommandStatus>().future,
    );
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    await _confirmDoorCommand(tester);
    expect(commands.createCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();
    expect(commands.createCalls, 1);
    await _confirmDoorCommand(tester);
    expect(commands.createCalls, 2);
  });

  testWidgets(
    'favorite fills dialer and dial action only reports unavailable',
    (tester) async {
      await tester.pumpWidget(
        subject(
          favorites: const [Favorite(name: 'Casa', number: '101')],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Casa'));
      await tester.pumpAndSettle();

      expect(find.text('101'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      expect(
        find.text('Conexão com o InterBridge será implementada aqui.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('summary keeps technical and access information out of view', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        loadDetail: () async {
          return const ApiDeviceDetail(
            deviceId: deviceId,
            displayName: null,
            hardwareVersion: 'HW-HIDDEN',
            ownershipStatus: 'claimed',
            provisioningStatus: 'PROVISIONED',
            role: DeviceRole.owner,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('InterBridge'), findsWidgets);
    expect(find.textContaining(deviceId), findsNothing);
    expect(find.textContaining('Hardware'), findsNothing);
    expect(find.text('HW-HIDDEN'), findsNothing);
    expect(find.textContaining('Provisionamento'), findsNothing);
    expect(find.textContaining('PROVISIONED'), findsNothing);
    expect(find.textContaining('Papel'), findsNothing);
  });

  testWidgets('diagnostics reveals and copies the identifier explicitly', (
    tester,
  ) async {
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(find.text('••••0001'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Identificador do dispositivo, ••••0001'),
      findsOneWidget,
    );
    semantics.dispose();
    expect(find.text(deviceId), findsNothing);
    expect(clipboardCalls, isEmpty);

    await tester.tap(find.text('••••0001'));
    await tester.pumpAndSettle();
    expect(find.text(deviceId), findsOneWidget);
    expect(
      find.text('Use este identificador quando o suporte solicitar.'),
      findsOneWidget,
    );
    expect(clipboardCalls, isEmpty);

    await tester.tap(find.text('Copiar identificador'));
    await tester.pumpAndSettle();
    expect(clipboardCalls, hasLength(1));
    expect((clipboardCalls.single.arguments as Map)['text'], deviceId);
    expect(find.text('Identificador copiado.'), findsOneWidget);
  });

  testWidgets('diagnostics presents REVOKED as access attention, not failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        loadDetail: () async => const ApiDeviceDetail(
          deviceId: deviceId,
          displayName: 'Portaria',
          ownershipStatus: 'claimed',
          provisioningStatus: 'REVOKED',
          role: DeviceRole.owner,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(find.text('Acesso revogado'), findsOneWidget);
    expect(find.textContaining('REVOKED'), findsNothing);
    expect(find.textContaining('Falha na configuração'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  for (final role in DeviceRole.values) {
    testWidgets(
      'settings translates ${role.name} sharing permission without an action',
      (tester) async {
        await tester.pumpWidget(subject(role: role));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Configurações'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Acesso e compartilhamento'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text(friendlyDeviceRole(role)), findsOneWidget);
        expect(
          find.text(
            role == DeviceRole.member
                ? 'Você não tem permissão para compartilhar este dispositivo.'
                : 'Você tem permissão para gerenciar o compartilhamento. Esse recurso ainda não está disponível.',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Compartilhar'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Compartilhar'), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, 'Compartilhar'),
          findsNothing,
        );
      },
    );
  }

  for (final role in DeviceRole.values) {
    testWidgets(
      '${role.name.toUpperCase()} can edit the personal name with the same payload',
      (tester) async {
        String? sentName;
        await tester.pumpWidget(
          subject(
            role: role,
            onUpdateName: (id, displayName) async {
              sentName = displayName;
              return ApiDeviceDetail(
                deviceId: id,
                displayName: displayName,
                ownershipStatus: 'claimed',
                provisioningStatus: 'active',
                role: role,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Editar nome'), findsOneWidget);

        await tester.tap(find.byTooltip('Editar nome'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  Nome pessoal  ');
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await tester.pumpAndSettle();

        expect(sentName, 'Nome pessoal');
      },
    );
  }

  testWidgets('tapping edit opens the editor pre-filled with the name', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    expect(find.byType(EditDeviceNamePage), findsOneWidget);
    expect(find.text('Portaria'), findsOneWidget);
  });

  testWidgets('renaming updates the AppBar title and card immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        onUpdateName: (id, displayName) async => ApiDeviceDetail(
          deviceId: id,
          displayName: displayName,
          hardwareVersion: 'HW-2',
          ownershipStatus: 'claimed',
          provisioningStatus: 'active',
          role: DeviceRole.owner,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Minha casa');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.byType(EditDeviceNamePage), findsNothing);
    expect(find.widgetWithText(AppBar, 'Minha casa'), findsOneWidget);
    expect(find.text('Portaria'), findsNothing);
  });

  testWidgets('save is disabled for blank input and trims before sending', (
    tester,
  ) async {
    String? sentName;
    await tester.pumpWidget(
      subject(
        onUpdateName: (id, displayName) async {
          sentName = displayName;
          return ApiDeviceDetail(
            deviceId: id,
            displayName: displayName,
            ownershipStatus: 'claimed',
            provisioningStatus: 'active',
            role: DeviceRole.owner,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '  Minha casa  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    expect(sentName, 'Minha casa');
  });

  testWidgets('Usar nome padrão clears the custom name', (tester) async {
    String? sentName = 'unset';
    await tester.pumpWidget(
      subject(
        onUpdateName: (id, displayName) async {
          sentName = displayName;
          return ApiDeviceDetail(
            deviceId: id,
            displayName: displayName,
            ownershipStatus: 'claimed',
            provisioningStatus: 'active',
            role: DeviceRole.owner,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usar nome padrão'));
    await tester.pumpAndSettle();
    expect(sentName, isNull);
    expect(find.byType(EditDeviceNamePage), findsNothing);
    expect(find.widgetWithText(AppBar, 'InterBridge'), findsOneWidget);
  });

  testWidgets('save error keeps the typed name and shows a friendly message', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        onUpdateName: (id, displayName) async {
          throw StateError('safe fake failure');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Minha casa');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.byType(EditDeviceNamePage), findsOneWidget);
    expect(find.text('Minha casa'), findsOneWidget);
    expect(
      find.text('Não foi possível salvar o nome. Tente novamente.'),
      findsOneWidget,
    );
  });

  group('known-name reuse while a detail GET races navigation', () {
    const casaSummary = ApiDeviceSummary(
      deviceId: deviceId,
      displayName: 'Casa',
      role: DeviceRole.owner,
      status: MembershipStatus.active,
    );

    ApiDeviceDetail casaDetail() => const ApiDeviceDetail(
      deviceId: deviceId,
      displayName: 'Casa',
      ownershipStatus: 'claimed',
      provisioningStatus: 'active',
      role: DeviceRole.owner,
    );

    testWidgets(
      'shows the list-known name immediately while detail is still loading',
      (tester) async {
        final pendingDetail = Completer<ApiDeviceDetail>();
        await tester.pumpWidget(
          subject(
            listItems: [casaSummary],
            loadDetail: () => pendingDetail.future,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);
        expect(find.text('InterBridge'), findsNothing);

        pendingDetail.complete(casaDetail());
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);
      },
    );

    testWidgets('a known summary with no personal name shows the confirmed '
        '"InterBridge" default immediately, never the neutral loading title', (
      tester,
    ) async {
      const namelessSummary = ApiDeviceSummary(
        deviceId: deviceId,
        displayName: null,
        role: DeviceRole.owner,
        status: MembershipStatus.active,
      );
      final pendingDetail = Completer<ApiDeviceDetail>();
      await tester.pumpWidget(
        subject(
          listItems: [namelessSummary],
          loadDetail: () => pendingDetail.future,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(AppBar, 'InterBridge'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Dispositivo'), findsNothing);

      pendingDetail.complete(
        const ApiDeviceDetail(
          deviceId: deviceId,
          displayName: null,
          ownershipStatus: 'claimed',
          provisioningStatus: 'active',
          role: DeviceRole.owner,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'InterBridge'), findsOneWidget);
    });

    testWidgets('tapping the gear icon before detail resolves opens '
        '"Configurações de Casa"', (tester) async {
      final pendingDetail = Completer<ApiDeviceDetail>();
      await tester.pumpWidget(
        subject(
          listItems: [casaSummary],
          loadDetail: () => pendingDetail.future,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump();
      await tester.pump();

      expect(
        find.widgetWithText(AppBar, 'Configurações de Casa'),
        findsOneWidget,
      );
      expect(find.textContaining('InterBridge'), findsNothing);
    });

    testWidgets(
      'entering Notificações immediately never shows InterBridge as the '
      'name',
      (tester) async {
        final pendingDetail = Completer<ApiDeviceDetail>();
        await tester.pumpWidget(
          subject(
            listItems: [casaSummary],
            loadDetail: () => pendingDetail.future,
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip('Configurações'));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Notificações'));
        await tester.pump();
        await tester.pump();

        expect(find.byType(NotificationPreferencesPage), findsOneWidget);
        expect(find.textContaining('InterBridge'), findsNothing);
      },
    );

    testWidgets(
      'when the confirmed detail arrives with the same name there is no '
      'visual change',
      (tester) async {
        await tester.pumpWidget(
          subject(
            listItems: [casaSummary],
            loadDetail: () async => casaDetail(),
          ),
        );
        await tester.pump();
        expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);
      },
    );

    testWidgets(
      'opened directly with no known summary shows a neutral title while '
      'loading, then the confirmed name once detail resolves',
      (tester) async {
        final pendingDetail = Completer<ApiDeviceDetail>();
        await tester.pumpWidget(
          subject(loadDetail: () => pendingDetail.future),
        );
        await tester.pump();

        expect(find.widgetWithText(AppBar, 'Dispositivo'), findsOneWidget);
        expect(find.text('Casa'), findsNothing);
        expect(find.text('InterBridge'), findsNothing);

        pendingDetail.complete(casaDetail());
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Dispositivo'), findsNothing);
      },
    );

    testWidgets(
      'a deep link into the device route works without GoRouterState.extra',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceRepositoryProvider.overrideWithValue(
                _DeviceDirectory(role: DeviceRole.owner),
              ),
              apiDeviceStatusProvider.overrideWith(
                (ref, id) async => ApiDeviceStatus(
                  deviceId: deviceId,
                  connectivity: DeviceConnectivity.recentlySeen,
                  freshness: DeviceFreshness.fresh,
                ),
              ),
              favoritesRepositoryProvider.overrideWithValue(
                _MemoryFavoritesRepository(const []),
              ),
              deviceSettingsRepositoryProvider.overrideWithValue(
                _SettingsRepository(Future.value(const DeviceSettings())),
              ),
              deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
                _NotificationPreferencesRepository(),
              ),
              doorDeviceAuthenticatorProvider.overrideWithValue(
                _Authenticator(),
              ),
              authSessionProvider.overrideWith(
                (ref) => Stream.value(const AuthSession(isSignedIn: true)),
              ),
              commandRepositoryProvider.overrideWithValue(_CommandRepository()),
            ],
            child: MaterialApp.router(
              routerConfig: GoRouter(
                initialLocation: '/devices/$deviceId',
                observers: [deviceDetailRouteObserver],
                routes: [
                  GoRoute(
                    path: '/devices/:deviceId',
                    builder: (_, state) => ApiDeviceDetailPage(
                      deviceId: state.pathParameters['deviceId']!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.widgetWithText(AppBar, 'Portaria'), findsOneWidget);
        expect(find.text('Receber ligação'), findsNothing);
      },
    );
  });
}

Future<void> _confirmDoorCommand(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
  await tester.pump();
  await tester.tap(find.text('Enviar solicitação'));
  await tester.pump();
}

class _ManualCooldownScheduler implements DoorCommandCooldownScheduler {
  VoidCallback? _callback;
  bool _cancelled = false;

  @override
  DoorCommandCooldown schedule(Duration duration, VoidCallback callback) {
    _callback = callback;
    return _ManualCooldown(() => _cancelled = true);
  }

  void elapse() {
    if (!_cancelled) _callback?.call();
  }
}

class _ManualCooldown implements DoorCommandCooldown {
  _ManualCooldown(this._onCancel);
  final VoidCallback _onCancel;

  @override
  void cancel() => _onCancel();
}
