import 'dart:convert';

import 'installation_id_store.dart' show StringPreferenceStore;

/// Defensive, best-effort protection against presenting the same
/// `RING_DETECTED` `event_id` twice locally.
///
/// This is **not** the source of truth for idempotency — the backend
/// already dedupes/suppresses at the source. This exists only to smooth
/// over FCM's at-least-once delivery guarantee (a retried or duplicated
/// delivery landing in both the foreground listener and the background
/// isolate handler, or twice in the same one).
abstract interface class RingEventDeduplicator {
  /// Returns `true` the first time [eventId] is seen within the dedup
  /// window (and records it), `false` on every later call for the same id.
  Future<bool> shouldPresent(String eventId);
}

/// Persists recently-seen event ids through [StringPreferenceStore] so the
/// check works across the main isolate and the separate background isolate
/// spawned for `firebaseMessagingBackgroundHandler` — plain in-memory state
/// would not be shared between them.
///
/// Limits, by design:
/// - [window] bounds *time*, [maxEntries] bounds *count* — this can never
///   grow unbounded even under a burst of distinct events.
/// - Only `event_id` + a timestamp are stored, never the payload.
/// - Reads/writes are not atomic across isolates. A genuinely concurrent
///   check for the *same* `event_id` from both isolates at once could each
///   observe "not seen yet" and both present. In practice the foreground
///   listener and the background handler are mutually exclusive for a
///   given app state, so this is a narrow, accepted gap — not a guarantee.
/// - A storage failure never throws; it just means this particular event
///   is not remembered for next time.
class SharedPreferencesRingEventDeduplicator implements RingEventDeduplicator {
  SharedPreferencesRingEventDeduplicator(
    this._store, {
    this.window = const Duration(seconds: 60),
    this.maxEntries = 50,
  });

  static const _preferenceKey = 'ring_detected_dedup_v1';

  /// Comfortably longer than the backend's ~30s FCM delivery TTL, to absorb
  /// delivery/processing jitter between the two isolates.
  final Duration window;
  final int maxEntries;
  final StringPreferenceStore _store;

  @override
  Future<bool> shouldPresent(String eventId) async {
    final now = DateTime.now().toUtc();
    final entries = _readEntries()
        .where((entry) => now.difference(entry.seenAt) <= window)
        .toList();

    if (entries.any((entry) => entry.eventId == eventId)) {
      await _write(entries);
      return false;
    }

    entries.add(_DedupEntry(eventId, now));
    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    await _write(trimmed);
    return true;
  }

  List<_DedupEntry> _readEntries() {
    final raw = _store.getString(_preferenceKey);
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
          .map(_DedupEntry.tryParse)
          .whereType<_DedupEntry>()
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _write(List<_DedupEntry> entries) async {
    try {
      await _store.setString(
        _preferenceKey,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
    } on Object {
      // Best-effort persistence only — see the class doc comment's limits.
    }
  }
}

class _DedupEntry {
  const _DedupEntry(this.eventId, this.seenAt);

  final String eventId;
  final DateTime seenAt;

  Map<String, Object> toJson() => {
    'id': eventId,
    'at': seenAt.millisecondsSinceEpoch,
  };

  static _DedupEntry? tryParse(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final at = map['at'];
    if (id is! String || at is! int) {
      return null;
    }
    return _DedupEntry(
      id,
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }
}
