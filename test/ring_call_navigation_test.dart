import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 8, 31, 12);
  final payload = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: occurredAt,
  ).serialize();

  test('logged-out tap opens after authorized login within maxAge', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    expect(coordinator.hasPending, isTrue);
    expect(coordinator.shouldOpen, isFalse);
    expect(authorizationCalls, 0);

    now = occurredAt.add(const Duration(minutes: 14));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(authorizationCalls, 1);
    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isTrue);
  });

  test('logged-out tap is discarded when login happens after maxAge', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    now = occurredAt.add(const Duration(minutes: 16));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
    expect(authorizationCalls, 0);
  });

  test('expired pending intent does not perform authorization', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    now = occurredAt.add(const Duration(hours: 1));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(authorizationCalls, 0);
  });

  test('discarded intent does not reopen on later auth changes', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    now = occurredAt.add(const Duration(minutes: 16));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);
    coordinator.setAuthenticated(false);
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
    expect(authorizationCalls, 0);
  });

  test('discards an unauthorized device', () async {
    final now = occurredAt;
    final coordinator = RingCallNavigationCoordinator(
      (_) async => false,
      now: () => now,
    );
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(payload);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
  });

  test('logout invalidates an authorization in flight', () async {
    final now = occurredAt;
    final result = Completer<bool>();
    final coordinator = RingCallNavigationCoordinator(
      (_) => result.future,
      now: () => now,
    );
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(payload);
    coordinator.setAuthenticated(false);
    result.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.shouldOpen, isFalse);
  });
}
