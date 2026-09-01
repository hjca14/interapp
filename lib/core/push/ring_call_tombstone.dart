import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable, best-effort record of which `call_id`s have already ended —
/// closes the ordering gap FCM/the background isolate cannot rule out:
/// `RING_ENDED(call_id=X)` arriving and being processed *before*
/// `RING_DETECTED(call_id=X)` (different `event_id`s, delivered through
/// different paths/isolates, with no ordering guarantee between them). A
/// plain in-memory `Set` would not survive that — the isolate that saw
/// `RING_ENDED` may not be the one that later sees `RING_DETECTED`, and
/// either may be a fresh isolate spun up after the app was fully closed.
///
/// This is deliberately narrower than [RingEventDeduplicator]
/// (`ring_event_deduplicator.dart`): that one suppresses a duplicate
/// delivery of the *same* `event_id`; this one suppresses a `RING_DETECTED`
/// for a `call_id` that a *different* `event_id` (its `RING_ENDED`) already
/// proved is over. Neither replaces the other — see `presentRingDetectedPush`
/// for how both are used together.
abstract interface class RingCallTombstoneStore {
  /// Durably marks [callId] as ended. Idempotent — marking an already-ended
  /// [callId] again (a duplicate/retried `RING_ENDED`) is a no-op in effect.
  Future<void> markEnded(String callId, {DateTime? at});

  /// Whether [callId] has been marked ended within [SharedPreferencesRingCallTombstoneStore.ttl].
  /// Always re-reads the durable store rather than an in-memory snapshot —
  /// see the implementation's doc comment for why that matters across
  /// isolates.
  Future<bool> isEnded(String callId);
}

/// Persists tombstones through [SharedPreferences] directly (not the
/// [StringPreferenceStore]-typed abstraction the deduplicator uses), because
/// [isEnded] specifically needs [SharedPreferences.reload] — something that
/// narrower interface does not expose.
///
/// Why [reload] matters here specifically: the legacy `shared_preferences`
/// API caches the entire preferences map in memory *per isolate* the first
/// time `SharedPreferences.getInstance()` is called in that isolate, and
/// every plain read afterward is served from that in-memory copy — it is
/// never implicitly refreshed from native storage. The main isolate's
/// [SharedPreferences] instance is typically obtained once and then reused
/// for the rest of the app session (see [ringCallTombstoneStoreProvider] in
/// `push_providers.dart`). If a *different* isolate — the background
/// handler, spawned fresh per FCM message — later writes a tombstone, the
/// main isolate's long-lived cached copy would never see it on a plain
/// `getString` call, silently defeating the whole point of this class.
/// [SharedPreferences.reload] forces a fresh native fetch into that same
/// cached instance, so [isEnded] always observes what any isolate most
/// recently wrote. [markEnded] does not need this: a write updates the
/// local cache of *this* isolate immediately, and durability for other
/// isolates comes from the native persistence itself, observed by their own
/// next [isEnded] call.
///
/// Bounded by design, same reasoning as the deduplicator:
/// - [ttl] bounds *time* (default 30 minutes — generous next to `call_id`
///   being unique per session and the backend's own push TTL of ~30
///   seconds, per `docs/PHASE_3_ROADMAP.md`, so a tombstone is never the
///   limiting factor on how "fresh" a redelivered `RING_DETECTED` can be);
/// - [maxEntries] bounds *count*, so this can never grow unbounded even
///   under an unlikely burst of distinct calls;
/// - only `call_id` + a timestamp are stored, never any push content;
/// - a storage failure never throws. [isEnded] fails **open** (returns
///   `false`, i.e. "not known to have ended") rather than closed: this is a
///   best-effort safety net layered on top of the backend's own
///   correlation, and a storage hiccup blocking every legitimate call would
///   be a far worse regression than the rare mis-ordering this exists to
///   catch. [markEnded] failing silently is already covered by
///   `IncomingCallNotificationService.endCall`'s own notification-cancel
///   call remaining independently reachable.
/// - concurrency: a read-modify-write is not atomic across isolates (same
///   caveat as the deduplicator). A [markEnded] and an [isEnded] for the
///   *same* `call_id` racing at the exact same instant could still let a
///   `RING_DETECTED` through right as its `RING_ENDED` is being recorded —
///   this class does not claim cross-isolate atomicity, only that a
///   `RING_ENDED` durably recorded *before* a later [isEnded] call is
///   guaranteed to be observed by it (via [reload]).
class SharedPreferencesRingCallTombstoneStore
    implements RingCallTombstoneStore {
  SharedPreferencesRingCallTombstoneStore(
    this._preferences, {
    this.ttl = const Duration(minutes: 30),
    this.maxEntries = 50,
  });

  static const _preferenceKey = 'ring_call_tombstones_v1';

  final Duration ttl;
  final int maxEntries;
  final SharedPreferences _preferences;

  @override
  Future<void> markEnded(String callId, {DateTime? at}) async {
    try {
      final now = (at ?? DateTime.now()).toUtc();
      final entries =
          _readEntries()
              .where((entry) => now.difference(entry.endedAt) <= ttl)
              .toList()
            ..removeWhere((entry) => entry.callId == callId);
      entries.add(_TombstoneEntry(callId, now));
      final trimmed = entries.length > maxEntries
          ? entries.sublist(entries.length - maxEntries)
          : entries;
      await _write(trimmed);
    } on Object {
      // Best-effort on purpose — see the class doc comment's limits.
    }
  }

  @override
  Future<bool> isEnded(String callId) async {
    try {
      // See the class doc comment: without this, a tombstone written by a
      // different isolate could be invisible to this one indefinitely.
      await _preferences.reload();
      final now = DateTime.now().toUtc();
      return _readEntries().any(
        (entry) =>
            entry.callId == callId && now.difference(entry.endedAt) <= ttl,
      );
    } on Object {
      // Fail open — see the class doc comment's limits.
      return false;
    }
  }

  List<_TombstoneEntry> _readEntries() {
    final raw = _preferences.getString(_preferenceKey);
    if (raw == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map(_TombstoneEntry.tryParse)
          .whereType<_TombstoneEntry>()
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _write(List<_TombstoneEntry> entries) async {
    await _preferences.setString(
      _preferenceKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

class _TombstoneEntry {
  const _TombstoneEntry(this.callId, this.endedAt);

  final String callId;
  final DateTime endedAt;

  Map<String, Object> toJson() => {
    'call_id': callId,
    'at': endedAt.millisecondsSinceEpoch,
  };

  static _TombstoneEntry? tryParse(Map<dynamic, dynamic> map) {
    final callId = map['call_id'];
    final at = map['at'];
    if (callId is! String || at is! int) {
      return null;
    }
    return _TombstoneEntry(
      callId,
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }
}
