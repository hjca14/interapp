import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/device_event_navigation.dart';
import 'package:interapp/core/push/notification_tap_diagnostic.dart';

void main() {
  const deviceId = 'ib-${'a'}bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('a tap that arrives before authentication is confirmed is preserved, '
      'not discarded — no navigation target yet, and a diagnostic reports it '
      'is pending', () {
    final diagnostics = <NotificationTapDiagnostic>[];
    final coordinator = DeviceEventNavigationCoordinator(
      (_) async => true,
      onDiagnostic: diagnostics.add,
    );

    coordinator.acceptDeviceId(deviceId);

    expect(coordinator.target, isNull);
    expect(
      diagnostics.map((d) => d.reason),
      contains('pending_awaiting_authentication'),
    );
  });

  test('once authenticated, a pending intent for an authorized device resolves '
      'to a navigation target', () async {
    final coordinator = DeviceEventNavigationCoordinator((_) async => true);
    coordinator.acceptDeviceId(deviceId);

    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.target, deviceId);
  });

  test('an unauthorized/nonexistent device never becomes a navigation target, '
      'and a diagnostic reports it', () async {
    final diagnostics = <NotificationTapDiagnostic>[];
    final coordinator = DeviceEventNavigationCoordinator(
      (_) async => false,
      onDiagnostic: diagnostics.add,
    );
    coordinator.acceptDeviceId(deviceId);

    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.target, isNull);
    expect(diagnostics.map((d) => d.reason), contains('device_not_authorized'));
  });

  test('a device authorization check that throws is treated as unauthorized, '
      'never as a target', () async {
    final coordinator = DeviceEventNavigationCoordinator(
      (_) async => throw Exception('network unreachable'),
    );
    coordinator.acceptDeviceId(deviceId);

    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.target, isNull);
  });

  test('becoming unauthenticated (a real logout) discards any pending intent — '
      'it is never resumed after a subsequent login, matching '
      'RingCallNavigationCoordinator\'s own policy', () async {
    final coordinator = DeviceEventNavigationCoordinator((_) async => true);
    coordinator.acceptDeviceId(deviceId);

    coordinator.setAuthenticated(false);
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      coordinator.target,
      isNull,
      reason: 'the intent was discarded by the logout, not merely delayed',
    );
  });

  test(
    'consumed() clears the target so it is only ever navigated to once',
    () async {
      final coordinator = DeviceEventNavigationCoordinator((_) async => true);
      coordinator.acceptDeviceId(deviceId);
      coordinator.setAuthenticated(true);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.target, deviceId);

      coordinator.consumed();

      expect(coordinator.target, isNull);
    },
  );

  test('already authenticated when the tap arrives resolves immediately — no '
      'pending diagnostic is reported in that case', () async {
    final diagnostics = <NotificationTapDiagnostic>[];
    final coordinator = DeviceEventNavigationCoordinator(
      (_) async => true,
      onDiagnostic: diagnostics.add,
    );
    coordinator.setAuthenticated(true);

    coordinator.acceptDeviceId(deviceId);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.target, deviceId);
    expect(
      diagnostics.map((d) => d.reason),
      isNot(contains('pending_awaiting_authentication')),
    );
  });
}
