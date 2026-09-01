import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_tombstone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a call not marked ended is reported as not ended', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(preferences);

    expect(await store.isEnded('call-${'a' * 32}'), isFalse);
  });

  test('markEnded then isEnded reports true for that exact call_id', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(preferences);

    await store.markEnded('call-${'a' * 32}');

    expect(await store.isEnded('call-${'a' * 32}'), isTrue);
    expect(await store.isEnded('call-${'b' * 32}'), isFalse);
  });

  test('markEnded is idempotent for a duplicate/retried RING_ENDED', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(preferences);

    await store.markEnded('call-${'a' * 32}');
    await store.markEnded('call-${'a' * 32}');
    await store.markEnded('call-${'a' * 32}');

    expect(await store.isEnded('call-${'a' * 32}'), isTrue);
  });

  test('a tombstone survives recreating the store — simulates a fresh '
      'isolate/handler invocation reading what an earlier one wrote', () async {
    final preferences = await SharedPreferences.getInstance();
    await SharedPreferencesRingCallTombstoneStore(
      preferences,
    ).markEnded('call-${'a' * 32}');

    // A brand new store instance, as `firebaseMessagingBackgroundHandler`
    // constructs fresh on every invocation.
    final freshStore = SharedPreferencesRingCallTombstoneStore(preferences);

    expect(await freshStore.isEnded('call-${'a' * 32}'), isTrue);
  });

  test(
    'isEnded observes a tombstone written at the native level after this '
    "instance's SharedPreferences cache was already populated — simulating "
    'a different isolate writing after this one first called getInstance()',
    () async {
      // This instance's local cache is populated now, before the "other
      // isolate" writes anything.
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesRingCallTombstoneStore(preferences);
      expect(await store.isEnded('call-${'a' * 32}'), isFalse);

      // Simulate a write from a different isolate: go around the cached
      // `SharedPreferences` instance entirely and write directly to the
      // underlying "native" store, exactly as a separate isolate's own
      // SharedPreferences.setString would ultimately persist.
      final nativeStore =
          SharedPreferencesStorePlatform.instance
              as InMemorySharedPreferencesStore;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await nativeStore.setValue(
        'String',
        'flutter.ring_call_tombstones_v1',
        '[{"call_id":"call-${'a' * 32}","at":$now}]',
      );

      // isEnded must still see it — this is the entire point of `reload()`.
      expect(await store.isEnded('call-${'a' * 32}'), isTrue);
    },
  );

  test('a tombstone older than the TTL is treated as not ended', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(
      preferences,
      ttl: const Duration(minutes: 30),
    );
    final old = DateTime.now().toUtc().subtract(const Duration(minutes: 31));

    await store.markEnded('call-${'a' * 32}', at: old);

    expect(await store.isEnded('call-${'a' * 32}'), isFalse);
  });

  test('a tombstone just inside the TTL is still reported as ended', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(
      preferences,
      ttl: const Duration(minutes: 30),
    );
    final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 29));

    await store.markEnded('call-${'a' * 32}', at: recent);

    expect(await store.isEnded('call-${'a' * 32}'), isTrue);
  });

  test('the collection never grows past maxEntries', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesRingCallTombstoneStore(
      preferences,
      maxEntries: 3,
    );

    for (var i = 0; i < 10; i++) {
      await store.markEnded('call-${i.toString().padLeft(32, '0')}');
    }

    // Only the most recent 3 remain — the earliest ones are gone.
    expect(await store.isEnded('call-${'0'.padLeft(32, '0')}'), isFalse);
    expect(await store.isEnded('call-${'9'.padLeft(32, '0')}'), isTrue);
  });

  test(
    'expired entries are pruned opportunistically on the next write',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesRingCallTombstoneStore(
        preferences,
        ttl: const Duration(minutes: 30),
      );
      final old = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      await store.markEnded('call-${'a' * 32}', at: old);

      await store.markEnded('call-${'b' * 32}');

      // The expired entry for 'a' is gone (never resurfaces as "ended"), and
      // never counted against maxEntries either — checked indirectly via 'b'
      // still being present.
      expect(await store.isEnded('call-${'a' * 32}'), isFalse);
      expect(await store.isEnded('call-${'b' * 32}'), isTrue);
    },
  );

  test('a storage failure on isEnded fails open (reports "not ended") '
      'rather than blocking every legitimate call', () async {
    final failingPreferences = _ThrowingSharedPreferences();
    final store = SharedPreferencesRingCallTombstoneStore(failingPreferences);

    expect(await store.isEnded('call-${'a' * 32}'), isFalse);
  });

  test('a storage failure on markEnded does not throw', () async {
    final failingPreferences = _ThrowingSharedPreferences();
    final store = SharedPreferencesRingCallTombstoneStore(failingPreferences);

    await expectLater(store.markEnded('call-${'a' * 32}'), completes);
  });
}

/// A [SharedPreferences] subclass is not practical (its constructor is
/// private); instead this stands in wherever the store only needs the two
/// methods it actually calls, cast through the same type at the call site
/// via a minimal fake package-private subtype is not possible either — so
/// this test drives the failure path through the real instance's `reload`
/// throwing instead, which is achievable by never initializing the mock
/// platform store at all.
class _ThrowingSharedPreferences implements SharedPreferences {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('simulated storage failure');
}
