import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 8, 31, 12);
  RingCallIntent payloadFor({String callSuffix = 'a'}) => RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, callSuffix).join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: occurredAt,
  );
  final payload = payloadFor().serialize();

  test(
    'logged-out tap opens after authorized login within the ring timeout',
    () async {
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

      now = occurredAt.add(const Duration(seconds: 45));
      coordinator.setAuthenticated(true);
      await Future<void>.delayed(Duration.zero);

      expect(authorizationCalls, 1);
      expect(coordinator.hasPending, isFalse);
      expect(coordinator.shouldOpen, isTrue);
      coordinator.dispose();
    },
  );

  test('logged-out tap is discarded when login happens after the ring '
      'timeout', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    now = occurredAt.add(const Duration(seconds: 61));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
    expect(authorizationCalls, 0);
    coordinator.dispose();
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
    coordinator.dispose();
  });

  test('discarded intent does not reopen on later auth changes', () async {
    var now = occurredAt;
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => now);

    coordinator.acceptSerialized(payload);
    now = occurredAt.add(const Duration(seconds: 61));
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);
    coordinator.setAuthenticated(false);
    coordinator.setAuthenticated(true);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.hasPending, isFalse);
    expect(coordinator.shouldOpen, isFalse);
    expect(authorizationCalls, 0);
    coordinator.dispose();
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
    coordinator.dispose();
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
    coordinator.dispose();
  });

  group('isValidating', () {
    test('true only while authenticated and a call is still being '
        'authorized', () async {
      final now = occurredAt;
      final result = Completer<bool>();
      final coordinator = RingCallNavigationCoordinator(
        (_) => result.future,
        now: () => now,
      );

      coordinator.acceptSerialized(payload);
      expect(
        coordinator.isValidating,
        isFalse,
        reason: 'not authenticated yet',
      );

      coordinator.setAuthenticated(true);
      expect(coordinator.isValidating, isTrue);

      result.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(
        coordinator.isValidating,
        isFalse,
        reason: 'now active, not pending',
      );
      coordinator.dispose();
    });
  });

  group('ring timeout (60s local fallback)', () {
    test('a call still ringing is ended automatically after 60s from '
        'occurredAt', () {
      fakeAsync((async) {
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => occurredAt.add(async.elapsed),
        );
        coordinator.setAuthenticated(true);
        coordinator.acceptSerialized(payload);
        async.elapse(Duration.zero);
        expect(coordinator.shouldOpen, isTrue);

        async.elapse(const Duration(seconds: 60));

        expect(coordinator.shouldOpen, isFalse);
        expect(coordinator.hasPending, isFalse);
        coordinator.dispose();
      });
    });

    test('answering/dismissing before the timeout cancels it — it never '
        'fires later', () {
      fakeAsync((async) {
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => occurredAt.add(async.elapsed),
        );
        coordinator.setAuthenticated(true);
        coordinator.acceptSerialized(payload);
        async.elapse(Duration.zero);
        coordinator.consumed();

        var notifiedAfterConsumed = false;
        coordinator.addListener(() => notifiedAfterConsumed = true);
        async.elapse(const Duration(seconds: 60));

        expect(notifiedAfterConsumed, isFalse);
        coordinator.dispose();
      });
    });

    test('a payload already older than 60s when accepted ends immediately, '
        'not after another 60s', () {
      fakeAsync((async) {
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () =>
              occurredAt.add(const Duration(seconds: 65)).add(async.elapsed),
        );
        coordinator.setAuthenticated(true);
        coordinator.acceptSerialized(payload);

        async.elapse(Duration.zero);

        expect(coordinator.hasPending, isFalse);
        expect(coordinator.shouldOpen, isFalse);
        coordinator.dispose();
      });
    });
  });

  group('endCall', () {
    test(
      'ends the matching pending call, aborting an in-flight open',
      () async {
        final result = Completer<bool>();
        final coordinator = RingCallNavigationCoordinator(
          (_) => result.future,
          now: () => occurredAt,
        );
        coordinator.setAuthenticated(true);
        coordinator.acceptSerialized(payload);
        expect(coordinator.hasPending, isTrue);

        coordinator.endCall(payloadFor().callId);
        result.complete(true);
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.hasPending, isFalse);
        expect(coordinator.shouldOpen, isFalse);
        coordinator.dispose();
      },
    );

    test('ends the matching active call', () async {
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => occurredAt,
      );
      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(payload);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.shouldOpen, isTrue);

      coordinator.endCall(payloadFor().callId);

      expect(coordinator.shouldOpen, isFalse);
      coordinator.dispose();
    });

    test('a stale end for an earlier call never cancels a newer one', () async {
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => occurredAt,
      );
      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(payloadFor(callSuffix: '1').serialize());
      await Future<void>.delayed(Duration.zero);
      coordinator.acceptSerialized(payloadFor(callSuffix: '2').serialize());
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.shouldOpen, isTrue);
      expect(coordinator.active?.callId, payloadFor(callSuffix: '2').callId);

      // A late RING_ENDED for the superseded call 1 must not touch call 2.
      coordinator.endCall(payloadFor(callSuffix: '1').callId);

      expect(coordinator.shouldOpen, isTrue);
      expect(coordinator.active?.callId, payloadFor(callSuffix: '2').callId);
      coordinator.dispose();
    });

    test('an end for a call this coordinator never held is a no-op', () async {
      final coordinator = RingCallNavigationCoordinator(
        (_) async => true,
        now: () => occurredAt,
      );
      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(payload);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.shouldOpen, isTrue);

      coordinator.endCall('call-${List.filled(32, 'f').join()}');

      expect(coordinator.shouldOpen, isTrue);
      coordinator.dispose();
    });

    test('RING_ENDED arriving before the pending open finishes aborts it — '
        'the authorization result is discarded', () async {
      final result = Completer<bool>();
      final coordinator = RingCallNavigationCoordinator(
        (_) => result.future,
        now: () => occurredAt,
      );
      coordinator.setAuthenticated(true);
      coordinator.acceptSerialized(payload);

      coordinator.endCall(payloadFor().callId);
      result.complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.shouldOpen, isFalse);
      expect(coordinator.hasPending, isFalse);
      coordinator.dispose();
    });
  });

  test('tapping the already-active call again is a no-op — no re-validation '
      'flicker', () async {
    var authorizationCalls = 0;
    final coordinator = RingCallNavigationCoordinator((_) async {
      authorizationCalls++;
      return true;
    }, now: () => occurredAt);
    coordinator.setAuthenticated(true);
    coordinator.acceptSerialized(payload);
    await Future<void>.delayed(Duration.zero);
    expect(authorizationCalls, 1);

    coordinator.acceptSerialized(payload);

    expect(authorizationCalls, 1);
    expect(coordinator.shouldOpen, isTrue);
    coordinator.dispose();
  });
}
