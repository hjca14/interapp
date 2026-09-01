import 'package:flutter_test/flutter_test.dart';
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

Map<String, dynamic> _validPayload({
  String eventId = 'evt-0123456789abcdef0123456789abcdef',
  String presentationIntent = 'RING_ONLY',
}) => {
  'push_contract_version': '1',
  'event': 'RING_DETECTED',
  'event_id': eventId,
  'device_id': 'ib-fedcba9876543210fedcba9876543210',
  'presentation_intent': presentationIntent,
  'occurred_at': '2026-08-30T12:00:00Z',
};

final _fixedNow = DateTime.parse('2026-08-30T12:00:05Z');

void main() {
  late FakeRingNotificationPresenter presenter;
  late FakeRingEventDeduplicator deduplicator;
  late List<RingPushDiagnostic> diagnostics;

  setUp(() {
    presenter = FakeRingNotificationPresenter();
    deduplicator = FakeRingEventDeduplicator();
    diagnostics = [];
  });

  Future<void> run(Map<String, dynamic> data, {String path = 'foreground'}) {
    return presentRingDetectedPush(
      data: data,
      presenter: presenter,
      deduplicator: deduplicator,
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
    Map<String, dynamic> endedPayload({
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

    test('reaches endCall, not present', () async {
      await run(endedPayload());

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

    test('a duplicate RING_ENDED (same event_id) is idempotent — endCall '
        'runs only once', () async {
      final payload = endedPayload();

      await run(payload);
      await run(payload);

      expect(presenter.ended, hasLength(1));
      expect(diagnostics.last.reason, 'duplicate_event_id');
    });

    test('an endCall failure releases the reservation for retry', () async {
      presenter.endCallError = Exception('plugin exploded');

      await run(endedPayload());
      expect(presenter.ended, isEmpty);

      presenter.endCallError = null;
      await run(endedPayload());

      expect(presenter.ended, hasLength(1));
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
