import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/presentation/pages/device_settings_page.dart';
import 'package:interapp/features/devices/presentation/pages/notification_preferences_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

class _RemoteRepository implements DeviceNotificationPreferencesRepository {
  _RemoteRepository(this.value);

  DeviceNotificationPreferences value;
  Completer<DeviceNotificationPreferences>? pendingGet;
  Object? getError;
  int getCalls = 0;
  int patchCalls = 0;

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async {
    getCalls++;
    if (getError case final Object error) throw error;
    return pendingGet?.future ?? value;
  }

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    patchCalls++;
    return draft;
  }
}

class _LocalRepository implements DeviceSettingsRepository {
  _LocalRepository([this.value = const DeviceSettings()]);

  DeviceSettings value;

  @override
  Future<DeviceSettings> get(String deviceId) async => value;

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {
    value = settings;
  }
}

class _Devices implements DeviceRepository {
  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async {
    return ApiDeviceDetail(
      deviceId: deviceId,
      displayName: 'Portaria',
      hardwareVersion: '1',
      ownershipStatus: 'claimed',
      provisioningStatus: 'active',
      role: DeviceRole.owner,
    );
  }

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async {
    return const ApiDevicePage(items: []);
  }

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) => getDeviceDetails(deviceId);
}

Widget _subject(_RemoteRepository remote, _LocalRepository local) {
  return ProviderScope(
    overrides: [
      deviceNotificationPreferencesRepositoryProvider.overrideWithValue(remote),
      deviceSettingsRepositoryProvider.overrideWithValue(local),
      deviceRepositoryProvider.overrideWithValue(_Devices()),
    ],
    child: const MaterialApp(home: DeviceSettingsPage(deviceId: 'device')),
  );
}

void main() {
  testWidgets(
    'the main settings screen offers only a "Notificações" entry, never the '
    'alert cards, and never triggers the remote GET',
    (tester) async {
      final remote = _RemoteRepository(DeviceNotificationPreferences());
      await tester.pumpWidget(_subject(remote, _LocalRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Notificações'), findsOneWidget);
      expect(find.text('Ligação, notificações e horários'), findsOneWidget);
      expect(find.text('Alertas'), findsNothing);
      expect(find.text('Horários sem ligação'), findsNothing);
      expect(find.text('Receber ligação'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Salvar'), findsNothing);
      expect(find.text('Porta'), findsOneWidget);
      expect(find.text('Acesso e compartilhamento'), findsOneWidget);
      expect(find.text('Dispositivo'), findsOneWidget);
      expect(
        remote.getCalls,
        0,
        reason: 'opening the main settings page must never GET remote prefs',
      );
    },
  );

  testWidgets('local device settings render independently even when the remote '
      'notification preferences API is unavailable', (tester) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences())
      ..getError = Exception('backend down');
    await tester.pumpWidget(_subject(remote, _LocalRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Porta'), findsOneWidget);
    expect(find.text('Ativar abertura de porta'), findsOneWidget);
    expect(find.text('Confirmar antes de abrir'), findsNothing);
    expect(find.text('Acesso e compartilhamento'), findsOneWidget);
    expect(find.text('Dispositivo'), findsOneWidget);
    expect(remote.getCalls, 0);
  });

  testWidgets('door settings expand only after local opt-in and retain values', (
    tester,
  ) async {
    final local = _LocalRepository(
      const DeviceSettings(
        confirmBeforeOpeningDoor: false,
        requireDeviceAuthenticationToOpenDoor: true,
      ),
    );
    await tester.pumpWidget(
      _subject(_RemoteRepository(DeviceNotificationPreferences()), local),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmar antes de abrir'), findsNothing);
    expect(find.text('Exigir autenticação do aparelho'), findsNothing);

    await tester.tap(find.text('Ativar abertura de porta'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar antes de abrir'), findsOneWidget);
    expect(find.text('Exigir autenticação do aparelho'), findsOneWidget);
    expect(local.value.confirmBeforeOpeningDoor, isFalse);
    expect(local.value.requireDeviceAuthenticationToOpenDoor, isTrue);

    await tester.tap(find.text('Ativar abertura de porta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativar abertura de porta'));
    await tester.pumpAndSettle();
    expect(local.value.confirmBeforeOpeningDoor, isFalse);
    expect(local.value.requireDeviceAuthenticationToOpenDoor, isTrue);
  });

  testWidgets('tapping the entry opens the dedicated Notificações page', (
    tester,
  ) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences());
    await tester.pumpWidget(_subject(remote, _LocalRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notificações'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationPreferencesPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Notificações'), findsOneWidget);
    expect(
      remote.getCalls,
      1,
      reason: 'opening the dedicated page is what triggers the GET',
    );
  });
}
