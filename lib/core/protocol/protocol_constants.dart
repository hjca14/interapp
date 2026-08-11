import 'dart:math';

/// The custom application-message protocol version, per
/// `docs/communication-protocol.md` §14/§33. Every custom JSON message the
/// backend/device exchange carries this; AWS-reserved contracts (Shadow,
/// Jobs, Fleet Provisioning) are versioned by AWS itself, not this field.
///
/// Centralized here so the number `1` isn't duplicated across the app —
/// compare against this constant instead of a literal.
const int kProtocolVersion = 1;

/// Whether [version] — a parsed message's `protocol_version` field — is one
/// this app understands. `null` counts as unsupported: every custom
/// application message is required to carry the field (§14).
bool isSupportedProtocolVersion(int? version) => version == kProtocolVersion;

/// Thrown when a message's `protocol_version` isn't one this app
/// understands. Mirrors the protocol's own failure mode (§33: "Unsupported
/// versions fail safely with UNSUPPORTED_PROTOCOL_VERSION").
class UnsupportedProtocolVersionException implements Exception {
  const UnsupportedProtocolVersionException(this.version);

  final int? version;

  @override
  String toString() => 'UnsupportedProtocolVersionException(version: $version)';
}

/// Maximum validity window the protocol allows for each command, per
/// `docs/communication-protocol.md` §18. The backend is the one that stamps
/// `issued_at`/`expires_at` and enforces this — the app doesn't need to
/// replicate expiry logic locally, this is just for reference/UI hints.
const Duration kOpenDoorMaxValidity = Duration(seconds: 10);
const Duration kRestartMaxValidity = Duration(seconds: 60);

final Random _idRandom = Random.secure();

/// Generates a `cmd-<32 hex chars>` identifier, matching the protocol's
/// "128-bit random value, lowercase hex, semantic prefix" id format (§14).
///
/// The app mints this client-side when issuing a command, so it can serve as
/// an idempotency key the backend correlates responses against — the
/// protocol doesn't mandate who generates it, but a client-generated id is
/// the standard way to make a "create/issue command" API call safely
/// retryable.
String generateCommandId() => 'cmd-${_randomHex128Bits()}';

/// Generates an `evt-<32 hex chars>` identifier, matching the same format
/// used for device-originated event ids (§14). The app itself doesn't emit
/// device events — this exists for tests/fakes that need to stand in for a
/// backend emitting one.
String generateEventId() => 'evt-${_randomHex128Bits()}';

String _randomHex128Bits() {
  final bytes = List<int>.generate(16, (_) => _idRandom.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
