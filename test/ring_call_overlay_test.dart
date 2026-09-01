import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:interapp/features/devices/presentation/pages/incoming_call_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/devices/presentation/widgets/ring_call_overlay.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

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
  Future<ApiDeviceDetail> updateDeviceName(String deviceId, String? name) =>
      getDeviceDetails(deviceId);
}

class _Settings implements DeviceSettingsRepository {
  const _Settings();

  @override
  Future<DeviceSettings> get(String deviceId) async => const DeviceSettings();

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  setUp(() {
    // Dispensar/Atender call IncomingCallNotificationService.cancelRing,
    // which needs a registered platform instance — see
    // incoming_call_notification_service_ring_test.dart.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  final intent = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, 'c').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: DateTime.utc(2026, 8, 31),
  );

  /// Mirrors how `InterApp` stacks [RingCallOverlay] over the app's own
  /// content via `MaterialApp.router`'s `builder` — see `app.dart`. Using a
  /// plain `Navigator` (pushing [underneath] then never popping it) here
  /// stands in for that "whatever route/stack was already open" content,
  /// without needing a full `GoRouter`.
  Widget subject({
    required RingCallNavigationCoordinator coordinator,
    required Widget underneath,
  }) => ProviderScope(
    overrides: [
      ringCallNavigationCoordinatorProvider.overrideWithValue(coordinator),
      deviceRepositoryProvider.overrideWithValue(_Devices()),
      deviceSettingsRepositoryProvider.overrideWithValue(const _Settings()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) =>
            Stack(children: [underneath, const RingCallOverlay()]),
      ),
    ),
  );

  RingCallNavigationCoordinator coordinatorFixedAt(DateTime now) =>
      RingCallNavigationCoordinator((_) async => true, now: () => now);

  testWidgets('shows nothing when there is no pending or active call', (
    tester,
  ) async {
    final coordinator = coordinatorFixedAt(intent.occurredAt);
    await tester.pumpWidget(
      subject(coordinator: coordinator, underneath: const Text('Home')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Validando chamada…'), findsNothing);
    expect(find.byType(IncomingCallPage), findsNothing);
    coordinator.dispose();
  });

  testWidgets(
    'shows a neutral, opaque, non-interactive surface while validating — '
    'the screen underneath is blocked, matching the requirement that it '
    'must be neither visible nor clickable',
    (tester) async {
      final resolving = Completer<bool>();
      final coordinator = RingCallNavigationCoordinator(
        (_) => resolving.future,
        now: () => intent.occurredAt,
      );
      var homeTapped = false;

      await tester.pumpWidget(
        subject(
          coordinator: coordinator,
          underneath: GestureDetector(
            onTap: () => homeTapped = true,
            child: const Text('Home'),
          ),
        ),
      );
      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(intent.serialize());
      await tester.pump();

      expect(find.text('Validando chamada…'), findsOneWidget);

      // The validating surface sits on top and is opaque/hit-testable, so a
      // tap lands on it, never reaching "Home" underneath.
      await tester.tap(find.text('Validando chamada…'));
      expect(homeTapped, isFalse);

      resolving.complete(true);
      await tester.pumpAndSettle();
      coordinator.dispose();
    },
  );

  testWidgets('shows IncomingCallPage once the call is active', (tester) async {
    final coordinator = coordinatorFixedAt(intent.occurredAt);
    await tester.pumpWidget(
      subject(coordinator: coordinator, underneath: const Text('Home')),
    );
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(intent.serialize());
    await tester.pumpAndSettle();

    expect(find.byType(IncomingCallPage), findsOneWidget);
    coordinator.dispose();
  });

  testWidgets(
    'dismissing the call never navigates — the underlying screen/stack is '
    'exactly what it was before, never replaced by a redirect to home',
    (tester) async {
      final coordinator = coordinatorFixedAt(intent.occurredAt);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ringCallNavigationCoordinatorProvider.overrideWithValue(
              coordinator,
            ),
            deviceRepositoryProvider.overrideWithValue(_Devices()),
            deviceSettingsRepositoryProvider.overrideWithValue(
              const _Settings(),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Text('Home'),
            builder: (context, child) =>
                Stack(children: [?child, const RingCallOverlay()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate the user having navigated deep into the app already —
      // this is the "route/stack the call must not discard" from the bug
      // report.
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Device detail')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Device detail'), findsOneWidget);

      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(intent.serialize());
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsOneWidget);

      await tester.tap(find.text('Dispensar'));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(
        find.text('Device detail'),
        findsOneWidget,
        reason:
            'the previous screen is simply revealed again, never '
            'redirected away from',
      );
      coordinator.dispose();
    },
  );
}
