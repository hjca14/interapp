import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/presentation/pages/device_settings_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

class _RemoteRepository
    implements DeviceNotificationPreferencesRepository {
  _RemoteRepository(this.value);

  DeviceNotificationPreferences value;
  Completer<DeviceNotificationPreferences>? pendingGet;
  Object? getError;
  Completer<DeviceNotificationPreferences>? pendingPatch;
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
    return pendingPatch?.future ?? draft;
  }
}

class _LocalRepository implements DeviceSettingsRepository {
  DeviceSettings value = const DeviceSettings();

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

Widget subject(_RemoteRepository remote, _LocalRepository local) {
  return ProviderScope(
    overrides: [
      deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
        remote,
      ),
      deviceSettingsRepositoryProvider.overrideWithValue(local),
      deviceRepositoryProvider.overrideWithValue(_Devices()),
    ],
    child: const MaterialApp(
      home: DeviceSettingsPage(deviceId: 'device', deviceName: 'Portaria'),
    ),
  );
}

void main() {
  testWidgets('remote loading does not hide local cards', (tester) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences())
      ..pendingGet = Completer<DeviceNotificationPreferences>();
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();

    expect(find.text('Alertas'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Porta'), findsOneWidget);
    expect(find.text('Acesso e compartilhamento'), findsOneWidget);
    expect(find.text('Dispositivo'), findsOneWidget);
  });

  testWidgets('remote error keeps local cards and offers retry', (tester) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences())
      ..getError = const ApiFailure(ApiFailureKind.offline, 'Sem conexão.');
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Porta'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    remote.getError = null;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Receber ligação'), findsOneWidget);
  });

  testWidgets('alert switches edit draft and save only on explicit action', (
    tester,
  ) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences());
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();
    await tester.pump();

    final save = find.widgetWithText(FilledButton, 'Salvar');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.text('Receber ligação'));
    await tester.pump();
    expect(remote.patchCalls, 0);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pump();
    expect(remote.patchCalls, 1);
  });

  testWidgets('required wording is present and obsolete wording is absent', (
    tester,
  ) async {
    final schedule = QuietSchedule(
      enabled: true,
      timezone: 'America/Recife',
      days: const {1},
      startTime: ClockTime(hour: 22, minute: 0),
      endTime: ClockTime(hour: 7, minute: 0),
    );
    final remote = _RemoteRepository(
      DeviceNotificationPreferences(quietSchedule: schedule),
    );
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Horários sem ligação'), findsOneWidget);
    expect(find.text('Só notificação'), findsOneWidget);
    expect(find.text('Bloquear tudo'), findsOneWidget);
    expect(find.text('America/Recife'), findsOneWidget);
    expect(find.text('Presença'), findsNothing);
    expect(find.text('Notificação sem som'), findsNothing);
    expect(find.textContaining('rede local'), findsNothing);
  });

  testWidgets('saving disables controls and shows progress then success', (
    tester,
  ) async {
    final pending = Completer<DeviceNotificationPreferences>();
    final remote = _RemoteRepository(DeviceNotificationPreferences())
      ..pendingPatch = pending;
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Receber ligação'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pump();

    expect(find.text('Salvando...'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Receber ligação'),
      ).onChanged,
      isNull,
    );
    pending.complete(
      DeviceNotificationPreferences(
        alertMode: AlertMode.notificationOnly,
        updatedAt: DateTime.utc(2026, 8, 27),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Preferências salvas.'), findsOneWidget);
  });

  testWidgets('back navigation confirms unsaved draft discard', (tester) async {
    final remote = _RemoteRepository(DeviceNotificationPreferences());
    await tester.pumpWidget(subject(remote, _LocalRepository()));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Receber ligação'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    expect(find.text('Continuar editando'), findsOneWidget);
  });
}
