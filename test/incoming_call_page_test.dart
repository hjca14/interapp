import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/presentation/pages/incoming_call_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/devices/presentation/widgets/door_command_card.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

/// Records [cancelRing] calls instead of touching the real plugin (which
/// would need a registered platform instance in tests — see
/// `incoming_call_notification_service_ring_test.dart`).
class _RecordingNotificationService extends IncomingCallNotificationService {
  _RecordingNotificationService() : super(FlutterLocalNotificationsPlugin());

  final List<String> canceledCallIds = [];

  @override
  Future<void> cancelRing(String callId) async {
    canceledCallIds.add(callId);
  }
}

class _Devices implements DeviceRepository {
  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async =>
      ApiDeviceDetail(
        deviceId: deviceId,
        displayName: 'Portaria',
        ownershipStatus: 'claimed',
        provisioningStatus: 'active',
        role: DeviceRole.owner,
      );

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async =>
      const ApiDevicePage(items: []);

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) => getDeviceDetails(deviceId);
}

class _Settings implements DeviceSettingsRepository {
  const _Settings(this.value);
  final DeviceSettings value;

  @override
  Future<DeviceSettings> get(String deviceId) async => value;

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {}
}

void main() {
  final intent = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, 'c').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: DateTime.utc(2026, 8, 31),
  );

  Widget subject(
    DeviceSettings settings, {
    IncomingCallNotificationService? notificationService,
    RingCallNavigationCoordinator? coordinator,
    VoidCallback? onDismiss,
  }) => ProviderScope(
    overrides: [
      deviceRepositoryProvider.overrideWithValue(_Devices()),
      deviceSettingsRepositoryProvider.overrideWithValue(_Settings(settings)),
      if (notificationService != null)
        incomingCallNotificationServiceProvider.overrideWithValue(
          notificationService,
        ),
      if (coordinator != null)
        ringCallNavigationCoordinatorProvider.overrideWithValue(coordinator),
    ],
    child: MaterialApp(
      home: IncomingCallPage(intent: intent, onDismiss: onDismiss ?? () {}),
    ),
  );

  testWidgets('hides door action when local opt-in is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(subject(const DeviceSettings()));
    await tester.pumpAndSettle();

    expect(find.byType(DoorCommandCard), findsNothing);
    expect(find.text('Abrir porta'), findsNothing);
  });

  testWidgets(
    'Dispensar stops the ringtone (cancels the notification), ends the call '
    'in the coordinator, and calls onDismiss',
    (tester) async {
      final service = _RecordingNotificationService();
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => intent.occurredAt,
      );
      coordinator.setAuthenticated(true);
      await tester.runAsync(() async {
        coordinator.acceptSerialized(intent.serialize());
        await Future<void>.delayed(Duration.zero);
      });
      var dismissed = false;

      await tester.pumpWidget(
        subject(
          const DeviceSettings(),
          notificationService: service,
          coordinator: coordinator,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dispensar'));
      await tester.pump();

      expect(service.canceledCallIds, [intent.callId]);
      expect(coordinator.shouldOpen, isFalse);
      expect(dismissed, isTrue);
      coordinator.dispose();
    },
  );

  testWidgets(
    'Atender shows the honest "no audio yet" message and then ends the '
    'call exactly like Dispensar — ringtone/notification canceled, '
    'coordinator cleared, onDismiss called — never leaving the call screen '
    'open as if a session had connected',
    (tester) async {
      final service = _RecordingNotificationService();
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => intent.occurredAt,
      );
      coordinator.setAuthenticated(true);
      // Real async, not the fake-async clock testWidgets normally runs
      // under: the coordinator's authorization future only resolves once
      // real microtasks/timers actually run.
      await tester.runAsync(() async {
        coordinator.acceptSerialized(intent.serialize());
        await Future<void>.delayed(Duration.zero);
      });
      expect(coordinator.shouldOpen, isTrue, reason: 'setup: call is active');
      var dismissed = false;

      await tester.pumpWidget(
        subject(
          const DeviceSettings(),
          notificationService: service,
          coordinator: coordinator,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atender'));
      await tester.pump();

      expect(
        find.text('Áudio ainda não disponível nesta versão.'),
        findsOneWidget,
      );
      expect(service.canceledCallIds, [intent.callId]);
      expect(coordinator.shouldOpen, isFalse);
      expect(dismissed, isTrue);
      coordinator.dispose();
    },
  );

  testWidgets(
    'a RING_ENDED for the same call after Atender is an idempotent no-op '
    '— the coordinator no longer holds it',
    (tester) async {
      final service = _RecordingNotificationService();
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => intent.occurredAt,
      );
      coordinator.setAuthenticated(true);
      await tester.runAsync(() async {
        coordinator.acceptSerialized(intent.serialize());
        await Future<void>.delayed(Duration.zero);
      });

      await tester.pumpWidget(
        subject(
          const DeviceSettings(),
          notificationService: service,
          coordinator: coordinator,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atender'));
      await tester.pump();
      expect(coordinator.shouldOpen, isFalse);

      var notified = false;
      coordinator.addListener(() => notified = true);
      coordinator.endCall(intent.callId);

      expect(notified, isFalse, reason: 'nothing changed — already ended');
      coordinator.dispose();
    },
  );
}
