import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/pages/api_device_detail_page.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
import 'package:interapp/features/devices/presentation/providers/device_refresh_provider.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/commands/data/command_repository.dart';
import 'package:interapp/features/commands/domain/command_models.dart';
import 'package:interapp/features/commands/presentation/providers/door_command_provider.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:interapp/features/auth/presentation/providers/biometric_lock_providers.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
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
  }) {
    return ProviderScope(
      overrides: [
        apiDeviceDetailProvider.overrideWith((ref, id) async {
          if (loadDetail != null) return loadDetail();
          return ApiDeviceDetail(
            deviceId: deviceId,
            displayName: 'Portaria',
            hardwareVersion: 'HW-2',
            ownershipStatus: 'claimed',
            provisioningStatus: 'active',
            role: role,
          );
        }),
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
          _SettingsRepository(settings ?? Future.value(const DeviceSettings())),
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
    expect(find.text('Em espera'), findsOneWidget);
    expect(find.textContaining('.000'), findsNothing);
    expect(find.textContaining('RECENTLYSEEN'), findsNothing);
    expect(find.text('Discar'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
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
          const DeviceSettings(confirmBeforeOpeningDoor: false),
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
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    final failed = Completer<DeviceSettings>();
    await tester.pumpWidget(
      subject(commands: commands, settings: failed.future),
    );
    await tester.pump();
    failed.completeError(StateError('safe fake'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNull,
    );
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
