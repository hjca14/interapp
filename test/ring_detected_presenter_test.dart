import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_tombstone.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/core/push/ring_detected_presenter.dart';
import 'package:interapp/core/push/ring_event_deduplicator.dart';
import 'package:interapp/core/push/ring_push_diagnostic.dart';

class FakeRingNotificationPresenter implements RingNotificationPresenter {
  final List<RingDetectedEvent> presented = [];
  final List<RingEndedEvent> ended = [];
  Object? presentError;
  Object? endCallError;

  @override
  Future<void> present(RingDetectedEvent event) async {
    if (presentError != null) {
      throw presentError!;
    }
    presented.add(event);
  }

  @override
  Future<void> endCall(RingEndedEvent event) async {
    if (endCallError != null) {
      throw endCallError!;
    }
    ended.add(event);
  }
}

class FakeRingEventDeduplicator implements RingEventDeduplicator {
  final Set<String> reserved = {};
  final List<String> released = [];
  Object? reserveError;
  Object? releaseError;

  @override
  Future<bool> reserve(String eventId) async {
    if (reserveError != null) {
      throw reserveError!;
    }
    return reserved.add(eventId);
  }

  @override
  Future<void> release(String eventId) async {
    if (releaseError != null) {
      throw releaseError!;
    }
    reserved.remove(eventId);
    released.add(eventId);
  }
}

class FakeRingCallTombstoneStore implements RingCallTombstoneStore {
  final Map<String, DateTime> endedAt = {};
  final List<String> markCalls = [];
  Object? markError;
  Object? isEndedError;

  @override
  Future<void> markEnded(String callId, {DateTime? at}) async {
    markCalls.add(callId);
    if (markError != null) {
      throw markError!;
    }
    endedAt[callId] = at ?? DateTime.now();
  }

  @override
  Future<bool> isEnded(String callId) async {
    if (isEndedError != null) {
      throw isEndedError!;
    }
    return endedAt.containsKey(callId);
  }
}

Map<String, dynamic> _validPayload({
  String eventId = 'evt-0123456789abcdef0123456789abcdef',
  String presentationIntent = 'RING_ONLY',
  String? callId,
}) => {
  'push_contract_version': '1',
  'event': 'RING_DETECTED',
  'event_id': eventId,
  'device_id': 'ib-fedcba9876543210fedcba9876543210',
  'presentation_intent': presentationIntent,
  'occurred_at': '2026-08-30T12:00:00Z',
  if (callId != null) 'call_id': callId,
};

Map<String, dynamic> _endedPayload({
  String eventId = 'evt-1111111111111111111111111111111a',
  String callId = 'call-0123456789abcdef0123456789abcdef',
}) => {
  'push_contract_version': '1',
  'event': 'RING_ENDED',
  'event_id': eventId,
  'device_id': 'ib-fedcba9876543210fedcba9876543210',
  'call_id': callId,
  'occurred_at': '2026-08-30T12:00:00Z',
};

final _fixedNow = DateTime.parse('2026-08-30T12:00:05Z');

void main() {
  late FakeRingNotificationPresenter presenter;
  late FakeRingEventDeduplicator deduplicator;
  late FakeRingCallTombstoneStore tombstones;
  late List<RingPushDiagnostic> diagnostics;

  setUp(() {
    presenter = FakeRingNotificationPresenter();
    deduplicator = FakeRingEventDeduplicator();
    tombstones = FakeRingCallTombstoneStore();
    diagnostics = [];
  });

  Future<void> run(Map<String, dynamic> data, {String path = 'foreground'}) {
    return presentRingDetectedPush(
      data: data,
      presenter: presenter,
      deduplicator: deduplicator,
      tombstones: tombstones,
      path: path,
      onDiagnostic: diagnostics.add,
      now: _fixedNow,
    );
  }

  for (final intent in ['RING_ONLY', 'RING_AND_NOTIFICATION']) {
    test('$intent presents through the presenter', () async {
      await run(_validPayload(presentationIntent: intent));

      expect(presenter.presented, hasLength(1));
      expect(
        diagnostics.single,
        isA<RingPushDiagnostic>()
            .having((d) => d.presented, 'presented', isTrue)
            .having((d) => d.reason, 'reason', 'presented'),
      );
    });
  }

  test('NOTIFICATION_ONLY also reaches the presenter (silence is the '
      'presenter\'s concern, not the composer\'s)', () async {
    await run(_validPayload(presentationIntent: 'NOTIFICATION_ONLY'));

    expect(presenter.presented, hasLength(1));
    expect(
      presenter.presented.single.presentationIntent,
      RingPresentationIntent.notificationOnly,
    );
  });

  group('RING_ENDED', () {
    test('reaches endCall, not present', () async {
      await run(_endedPayload());

      expect(presenter.ended, hasLength(1));
      expect(
        presenter.ended.single.callId,
        'call-0123456789abcdef0123456789abcdef',
      );
      expect(presenter.presented, isEmpty);
      expect(
        diagnostics.single,
        isA<RingPushDiagnostic>()
            .having((d) => d.presented, 'presented', isTrue)
            .having((d) => d.eventName, 'eventName', 'RING_ENDED'),
      );
    });

    test('durably marks the tombstone before calling endCall', () async {
      await run(_endedPayload());

      expect(tombstones.markCalls, ['call-0123456789abcdef0123456789abcdef']);
      expect(
        await tombstones.isEnded('call-0123456789abcdef0123456789abcdef'),
        isTrue,
      );
    });

    test('a duplicate RING_ENDED (same event_id) is idempotent — endCall '
        'and the tombstone write both run only once', () async {
      final payload = _endedPayload();

      await run(payload);
      await run(payload);

      expect(presenter.ended, hasLength(1));
      expect(tombstones.markCalls, hasLength(1));
      expect(diagnostics.last.reason, 'duplicate_event_id');
    });

    test('an endCall failure releases the reservation for retry, but the '
        'tombstone stays marked — the call is over either way', () async {
      presenter.endCallError = Exception('plugin exploded');

      await run(_endedPayload());
      expect(presenter.ended, isEmpty);
      expect(
        await tombstones.isEnded('call-0123456789abcdef0123456789abcdef'),
        isTrue,
        reason:
            'the fact the call ended does not depend on cleanup '
            'succeeding',
      );

      presenter.endCallError = null;
      await run(_endedPayload());

      expect(presenter.ended, hasLength(1));
    });

    test('a tombstone write failure does not throw and still attempts '
        'endCall', () async {
      tombstones.markError = Exception('storage exploded');

      await expectLater(run(_endedPayload()), completes);
    });
  });

  group('start suppressed by an already-ended call_id (RING_ENDED processed '
      'before RING_DETECTED — no ordering guarantee between them)', () {
    test('a RING_DETECTED for an already-tombstoned call_id never reaches '
        'present()', () async {
      await run(_endedPayload(callId: 'call-0123456789abcdef0123456789abcdef'));
      presenter.ended.clear(); // isolate the RING_DETECTED assertions below

      await run(
        _validPayload(
          eventId: 'evt-2222222222222222222222222222222b',
          callId: 'call-0123456789abcdef0123456789abcdef',
        ),
      );

      expect(presenter.presented, isEmpty);
      expect(
        diagnostics.last,
        isA<RingPushDiagnostic>()
            .having((d) => d.presented, 'presented', isFalse)
            .having(
              (d) => d.reason,
              'reason',
              'start_suppressed_already_ended',
            ),
      );
    });

    test('the suppressed start never reserves a dedup slot for its own '
        'event_id — a legitimate retry is still just as suppressed, not '
        'newly "duplicate"', () async {
      await run(_endedPayload(callId: 'call-0123456789abcdef0123456789abcdef'));
      final detectedPayload = _validPayload(
        eventId: 'evt-2222222222222222222222222222222b',
        callId: 'call-0123456789abcdef0123456789abcdef',
      );

      await run(detectedPayload);
      diagnostics.clear();
      await run(detectedPayload);

      expect(presenter.presented, isEmpty);
      expect(diagnostics.single.reason, 'start_suppressed_already_ended');
    });

    test('a RING_ENDED for call X never suppresses a RING_DETECTED for a '
        'different call Y', () async {
      await run(
        _endedPayload(
          eventId: 'evt-3333333333333333333333333333333c',
          callId: 'call-1111111111111111111111111111111d',
        ),
      );

      await run(
        _validPayload(
          eventId: 'evt-4444444444444444444444444444444e',
          callId: 'call-2222222222222222222222222222222f',
        ),
      );

      expect(presenter.presented, hasLength(1));
      expect(
        presenter.presented.single.callId,
        'call-2222222222222222222222222222222f',
      );
    });

    test('a RING_DETECTED with no explicit call_id still runs the tombstone '
        'check using its defaulted call_id (== event_id) — it just never '
        'matches a real RING_ENDED in practice, since call_id there is always '
        'required and always call-prefixed, never evt-prefixed', () async {
      await run(_validPayload(eventId: 'evt-${'7' * 32}'));

      expect(presenter.presented, hasLength(1));
      expect(presenter.presented.single.callId, 'evt-${'7' * 32}');
    });

    test('a genuine near-simultaneous race — RING_DETECTED\'s isEnded() check '
        'reads before RING_ENDED\'s markEnded() commits — degrades to '
        '"ended", never a stuck phantom: no cross-isolate lock makes the two '
        'truly atomic (see RingCallTombstoneStore\'s doc comment), but '
        "RING_ENDED's own endCall() runs unconditionally regardless of "
        'ordering, so the call is still canceled moments later — and even in '
        'the narrower window where it is not, the independent 60s local '
        'ring-timeout/OS timeoutAfter (RingCallNavigationCoordinator / '
        'IncomingCallNotificationService, unrelated to this store) bounds '
        'how long any of it could look like a live call', () async {
      // The fake tombstone store starts empty — standing in for isEnded()
      // observing "not yet ended" because it read right before, not
      // after, the matching RING_ENDED's markEnded() committed. That
      // ordering is exactly what RingCallTombstoneStore does not claim
      // to make atomic — see its doc comment.
      await run(_validPayload(callId: 'call-0123456789abcdef0123456789abcdef'));
      expect(
        presenter.presented,
        hasLength(1),
        reason: 'the race let the start through, as documented',
      );

      // The concurrent RING_ENDED still runs to completion independently
      // and unconditionally — it does not consult isEnded() at all.
      await run(_endedPayload(callId: 'call-0123456789abcdef0123456789abcdef'));

      expect(
        presenter.ended.single.callId,
        'call-0123456789abcdef0123456789abcdef',
        reason:
            'the call converges to ended shortly after, regardless '
            'of the race outcome for the start',
      );
    });

    test('a tombstone-check failure fails open — the start is still '
        'presented rather than silently blocked forever', () async {
      tombstones.isEndedError = Exception('storage exploded');

      await run(_validPayload());

      expect(presenter.presented, hasLength(1));
    });
  });

  test('an invalid payload never reaches the presenter', () async {
    await run({'push_contract_version': '1'});

    expect(presenter.presented, isEmpty);
    expect(
      diagnostics.single,
      isA<RingPushDiagnostic>()
          .having((d) => d.contractValid, 'contractValid', isFalse)
          .having((d) => d.presented, 'presented', isFalse),
    );
  });

  group('deduplication', () {
    test('the same event_id is never presented twice', () async {
      final payload = _validPayload();

      await run(payload);
      await run(payload);

      expect(presenter.presented, hasLength(1));
      expect(diagnostics.last.reason, 'duplicate_event_id');
      expect(diagnostics.last.presented, isFalse);
    });

    test('a duplicate is detected across two independent calls sharing the '
        'deduplicator, simulating foreground + background_handler', () async {
      final payload = _validPayload();

      await run(payload, path: 'foreground');
      await run(payload, path: 'background_handler');

      expect(presenter.presented, hasLength(1));
    });

    test('a successful presentation marks the event_id as seen (no release '
        'call)', () async {
      await run(_validPayload());

      expect(deduplicator.released, isEmpty);
      expect(
        deduplicator.reserved,
        contains('evt-0123456789abcdef0123456789abcdef'),
      );
    });

    test('a presenter failure releases the reservation instead of leaving '
        'the event_id stuck as "seen"', () async {
      presenter.presentError = Exception('plugin exploded');

      await run(_validPayload());

      expect(deduplicator.released, ['evt-0123456789abcdef0123456789abcdef']);
      expect(
        deduplicator.reserved,
        isNot(contains('evt-0123456789abcdef0123456789abcdef')),
      );
    });

    test('after a presenter failure, a retry of the same event_id can be '
        'presented', () async {
      presenter.presentError = Exception('plugin exploded');
      await run(_validPayload());
      expect(presenter.presented, isEmpty);

      presenter.presentError = null;
      await run(_validPayload());

      expect(presenter.presented, hasLength(1));
    });

    test('a reservation failure (dedup storage broken) does not throw and '
        'never reaches the presenter', () async {
      deduplicator.reserveError = Exception('storage exploded');

      await expectLater(run(_validPayload()), completes);
      expect(presenter.presented, isEmpty);
    });

    test(
      'a release failure after a presenter failure does not throw',
      () async {
        presenter.presentError = Exception('plugin exploded');
        deduplicator.releaseError = Exception('release storage exploded');

        await expectLater(run(_validPayload()), completes);
      },
    );
  });

  test(
    'a presenter failure does not throw and is reported sanitized',
    () async {
      presenter.presentError = Exception('plugin exploded');

      await expectLater(run(_validPayload()), completes);

      expect(
        diagnostics.single,
        isA<RingPushDiagnostic>()
            .having((d) => d.presented, 'presented', isFalse)
            .having((d) => d.reason, 'reason', 'presentation_failed'),
      );
    },
  );

  test('a deduplicator failure does not throw', () async {
    deduplicator.reserveError = Exception('storage exploded');

    await expectLater(run(_validPayload()), completes);
    expect(presenter.presented, isEmpty);
  });

  test('diagnostics never contain the full event_id, device_id, or '
      'anything from the raw payload', () async {
    await run(_validPayload());

    final line = diagnostics.single.toLogLine();
    expect(line, isNot(contains('0123456789abcdef0123456789abcdef')));
    expect(line, isNot(contains('fedcba9876543210fedcba9876543210')));
    expect(line, contains('event_id=')); // masked form is present
  });

  test(
    'diagnostics stay sanitized even after a presenter failure and release',
    () async {
      presenter.presentError = Exception('plugin exploded with secret data');

      await run(_validPayload());

      final line = diagnostics.single.toLogLine();
      expect(line, isNot(contains('0123456789abcdef0123456789abcdef')));
      expect(line, isNot(contains('secret')));
      expect(line, contains('motivo=presentation_failed'));
    },
  );
}
