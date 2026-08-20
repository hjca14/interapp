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

class _MemoryFavoritesRepository extends LocalFavoritesRepository {
  _MemoryFavoritesRepository(this.values);
  final List<Favorite> values;

  @override
  Future<List<Favorite>> getAll(String deviceId) async => values;

  @override
  Future<void> saveAll(String deviceId, List<Favorite> favorites) async {}
}

void main() {
  const deviceId = 'ib-0000000000000000000000000001';

  Widget subject({List<Favorite> favorites = const []}) {
    return ProviderScope(
      overrides: [
        apiDeviceDetailProvider.overrideWith((ref, id) async {
          return const ApiDeviceDetail(
            deviceId: deviceId,
            displayName: 'Portaria',
            hardwareVersion: 'HW-2',
            ownershipStatus: 'claimed',
            provisioningStatus: 'active',
            role: DeviceRole.owner,
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
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Abrir')).onPressed,
      isNull,
    );
  });

  testWidgets('favorite fills dialer and dial action only reports unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(favorites: const [Favorite(name: 'Casa', number: '101')]),
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
  });
}
