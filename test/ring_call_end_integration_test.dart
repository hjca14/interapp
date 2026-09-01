import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/push_providers.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/repositories/device_repository.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

class _AuthorizingDevices implements DeviceRepository {
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

class _RecordingNotificationService extends IncomingCallNotificationService {
  _RecordingNotificationService() : super(FlutterLocalNotificationsPlugin());

  final List<String> canceledCallIds = [];

  @override
  Future<void> cancelRing(String callId) async {
    canceledCallIds.add(callId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lockScreenChannel = MethodChannel('interapp/ring_call_presentation');

  final intent = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, 'c').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: DateTime.utc(2026, 8, 31),
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockScreenChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockScreenChannel, null);
  });

  test('the internal 60s ring-timeout — which cancels nothing on its own — '
      'still cancels the notification and undoes the lock-screen bypass, via '
      'the integration listener', () async {
    final service = _RecordingNotificationService();
    var lockScreenCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockScreenChannel, (call) async {
          if (call.method == 'endPresentation') lockScreenCalls++;
          return null;
        });

    final container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(_AuthorizingDevices()),
        incomingCallNotificationServiceProvider.overrideWithValue(service),
        ringCallNavigationCoordinatorProvider.overrideWithValue(
          RingCallNavigationCoordinator(
            (_) async => true,
            now: () => intent.occurredAt,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(ringCallEndIntegrationProvider);
    final coordinator = container.read(ringCallNavigationCoordinatorProvider);

    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(intent.serialize());
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.shouldOpen, isTrue, reason: 'setup: call is active');

    // Fire the internal timer directly rather than waiting 60 real
    // seconds — endCall(callId) is exactly what the timer invokes.
    coordinator.endCall(intent.callId);
    await Future<void>.delayed(Duration.zero);

    expect(service.canceledCallIds, [intent.callId]);
    expect(lockScreenCalls, 1);
  });

  test('a call dropped while still pending (e.g. unauthorized device) also '
      'undoes the lock-screen bypass — MainActivity grants it from the '
      'payload alone, before authorization is known', () async {
    final service = _RecordingNotificationService();
    var lockScreenCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockScreenChannel, (call) async {
          if (call.method == 'endPresentation') lockScreenCalls++;
          return null;
        });

    final container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(_AuthorizingDevices()),
        incomingCallNotificationServiceProvider.overrideWithValue(service),
        ringCallNavigationCoordinatorProvider.overrideWithValue(
          RingCallNavigationCoordinator(
            (_) async => false, // unauthorized
            now: () => intent.occurredAt,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(ringCallEndIntegrationProvider);
    final coordinator = container.read(ringCallNavigationCoordinatorProvider);

    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(intent.serialize());
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
    expect(lockScreenCalls, 1);
  });
}
