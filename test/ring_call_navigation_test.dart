import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 12);
  final payload = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: now,
  ).serialize();

  test('keeps tap pending until authentication then authorizes', () async {
    var calls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      calls++;
      return true;
    });
    coordinator.acceptSerialized(payload, now: now);
    expect(coordinator.hasPending, isTrue);
    expect(coordinator.shouldOpen, isFalse);
    expect(calls, 0);
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(coordinator.shouldOpen, isTrue);
  });

  test('discards an unauthorized device', () async {
    final coordinator = RingCallNavigationCoordinator((_) async => false);
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(payload, now: now);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
  });

  test('logout invalidates an authorization in flight', () async {
    final result = Completer<bool>();
    final coordinator = RingCallNavigationCoordinator((_) => result.future);
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(payload, now: now);
    coordinator.setAuthenticated(false);
    result.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.shouldOpen, isFalse);
  });
}
