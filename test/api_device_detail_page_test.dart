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

class _MemoryFavoritesRepository extends LocalFavoritesRepository {
  _MemoryFavoritesRepository(this.values);
  final List<Favorite> values;

  @override
  Future<List<Favorite>> getAll(String deviceId) async => values;

  @override
  Future<void> saveAll(String deviceId, List<Favorite> favorites) async {}
}

class _CommandRepository implements CommandRepository {
  int createCalls = 0;

  @override
  Future<AcceptedCommand> createOpenDoorCommand(
    DeviceId deviceId,
    String idempotencyKey,
  ) async {
    createCalls++;
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
  ) async => CommandStatus(
    commandId: commandId,
    state: CommandState.rejected,
    rejection: const CommandRejection('CAPABILITY_DISABLED'),
  );
}

void main() {
  const deviceId = 'ib-00000000000000000000000000000001';

  Widget subject({
    List<Favorite> favorites = const [],
    DeviceRole role = DeviceRole.owner,
    CommandRepository? commands,
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
          (ref) => Stream.value(const AuthSession(isSignedIn: true)),
        ),
        commandRepositoryProvider.overrideWithValue(
          commands ?? _CommandRepository(),
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
