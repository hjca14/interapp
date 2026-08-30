import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/installation_id_store.dart';
import 'package:interapp/core/push/ring_event_deduplicator.dart';

class FakeStringPreferenceStore implements StringPreferenceStore {
  final Map<String, String> _values = {};
  bool failWrites = false;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (failWrites) {
      throw Exception('boom');
    }
    _values[key] = value;
    return true;
  }
}

void main() {
  late FakeStringPreferenceStore store;

  setUp(() {
    store = FakeStringPreferenceStore();
  });

  test('the first sighting of an event_id should be presented', () async {
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    expect(await deduplicator.shouldPresent('evt-a'), isTrue);
  });

  test('a second sighting of the same event_id is suppressed', () async {
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    expect(await deduplicator.shouldPresent('evt-a'), isTrue);
    expect(await deduplicator.shouldPresent('evt-a'), isFalse);
  });

  test('suppression is visible from a second instance sharing the store '
      '(simulates foreground vs. background isolate)', () async {
    final foreground = SharedPreferencesRingEventDeduplicator(store);
    final background = SharedPreferencesRingEventDeduplicator(store);

    expect(await foreground.shouldPresent('evt-a'), isTrue);
    expect(await background.shouldPresent('evt-a'), isFalse);
  });

  test('different event ids are independent', () async {
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    expect(await deduplicator.shouldPresent('evt-a'), isTrue);
    expect(await deduplicator.shouldPresent('evt-b'), isTrue);
  });

  test('an entry outside the window is treated as new again', () async {
    var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final deduplicator = SharedPreferencesRingEventDeduplicator(
      store,
      window: const Duration(seconds: 30),
    );

    // shouldPresent reads DateTime.now() internally; exercise the window by
    // constructing two deduplicators is not enough since "now" isn't
    // injectable here — instead verify the entry format directly ages out
    // by pre-seeding a stale entry through the store.
    await store.setString(
      'ring_detected_dedup_v1',
      '[{"id":"evt-a","at":${now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch}}]',
    );

    expect(await deduplicator.shouldPresent('evt-a'), isTrue);
  });

  test('the structure never grows past maxEntries', () async {
    final deduplicator = SharedPreferencesRingEventDeduplicator(
      store,
      maxEntries: 3,
    );

    for (var i = 0; i < 10; i++) {
      await deduplicator.shouldPresent('evt-$i');
    }

    final raw = store.getString('ring_detected_dedup_v1');
    expect(raw, isNotNull);
    // A cheap structural check without parsing JSON: at most 3 "id" keys.
    final occurrences = RegExp('"id"').allMatches(raw!).length;
    expect(occurrences, lessThanOrEqualTo(3));
  });

  test('never persists anything beyond the event id and a timestamp', () async {
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    await deduplicator.shouldPresent('evt-a');

    final raw = store.getString('ring_detected_dedup_v1');
    expect(raw, contains('evt-a'));
    expect(raw, isNot(contains('device_id')));
    expect(raw, isNot(contains('presentation_intent')));
    expect(raw, isNot(contains('token')));
  });

  test('a storage read failure (corrupt data) does not throw', () async {
    await store.setString('ring_detected_dedup_v1', 'not valid json{{{');
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    await expectLater(deduplicator.shouldPresent('evt-a'), completion(isTrue));
  });

  test('a storage write failure does not throw', () async {
    store.failWrites = true;
    final deduplicator = SharedPreferencesRingEventDeduplicator(store);

    await expectLater(deduplicator.shouldPresent('evt-a'), completion(isTrue));
  });
}
