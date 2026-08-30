import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/core/push/ring_detected_presenter.dart';
import 'package:interapp/core/push/ring_event_deduplicator.dart';
import 'package:interapp/core/push/ring_push_diagnostic.dart';

class FakeRingNotificationPresenter implements RingNotificationPresenter {
  final List<RingDetectedEvent> presented = [];
  Object? presentError;

  @override
  Future<void> present(RingDetectedEvent event) async {
    if (presentError != null) {
      throw presentError!;
    }
    presented.add(event);
  }
}

class FakeRingEventDeduplicator implements RingEventDeduplicator {
  final Set<String> seen = {};
  Object? shouldPresentError;

  @override
  Future<bool> shouldPresent(String eventId) async {
    if (shouldPresentError != null) {
      throw shouldPresentError!;
    }
    return seen.add(eventId);
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
    deduplicator.shouldPresentError = Exception('storage exploded');

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
}
