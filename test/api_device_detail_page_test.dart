import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';
import 'package:interapp/features/devices/presentation/pages/api_device_detail_page.dart';
import 'package:interapp/features/devices/presentation/providers/api_devices_provider.dart';
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

class _MemoryFavoritesRepository extends LocalFavoritesRepository {
  _MemoryFavoritesRepository(this.values);
  final List<Favorite> values;

  @override
  Future<List<Favorite>> getAll(String deviceId) async => values;

  @override
  Future<void> saveAll(String deviceId, List<Favorite> favorites) async {}
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
  }) {
    return ProviderScope(
      overrides: [
        apiDeviceDetailProvider.overrideWith((ref, id) async {
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
      ],
      child: const MaterialApp(home: ApiDeviceDetailPage(deviceId: deviceId)),
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
    expect(find.textContaining('RECENTLYSEEN'), findsOneWidget);
    expect(find.textContaining('2.0.1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
          .onPressed,
      isNotNull,
    );
  });

  for (final role in [DeviceRole.admin, DeviceRole.member]) {
    testWidgets('${role.name.toUpperCase()} cannot send a command', (
      tester,
    ) async {
      final commands = _CommandRepository();
      await tester.pumpWidget(subject(role: role, commands: commands));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir'))
            .onPressed,
        isNull,
      );
      expect(commands.createCalls, 0);
    });
  }

  testWidgets('cancel sends no POST and confirmation sends exactly one', (
    tester,
  ) async {
    final commands = _CommandRepository();
    await tester.pumpWidget(subject(commands: commands));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir porta?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(commands.createCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar solicitação'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(commands.createCalls, 1);
    expect(
      find.textContaining('A abertura ainda não está configurada'),
      findsOneWidget,
    );
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
  await tester.pumpAndSettle();
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
