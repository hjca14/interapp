/// The interfone's operating state as reported in the device's Device
/// Shadow (`intercom_state`), per `docs/communication-protocol.md` §22/§24.
///
/// Modeled as an open value wrapper instead of a closed `enum`: the
/// protocol document only ever shows one concrete example value (`"IDLE"`)
/// and does not enumerate the full state vocabulary. Hardcoding guessed
/// states (e.g. `RINGING`, `IN_CALL`) here would risk silently diverging
/// from whatever the firmware actually reports — see PROJECT_CONTEXT.md for
/// this open item. Instead, any string the backend sends round-trips
/// through [raw] without the app needing to recognize it, and [idle] is the
/// only named constant because it's the only value the protocol document
/// actually confirms.
class IntercomState {
  const IntercomState._(this.raw);

  /// No state has been reported yet. An app-local sentinel — not a value
  /// the firmware/backend ever sends.
  static const unreported = IntercomState._(null);

  /// The one state value the protocol document shows an example of
  /// (`docs/communication-protocol.md` §22).
  static const idle = IntercomState._('IDLE');

  factory IntercomState.fromRaw(String? raw) {
    if (raw == null) return unreported;
    if (raw == idle.raw) return idle;
    return IntercomState._(raw);
  }

  /// The exact string as reported by the backend, or `null` for
  /// [unreported].
  final String? raw;

  bool get isReported => raw != null;

  @override
  bool operator ==(Object other) => other is IntercomState && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => raw ?? 'unreported';
}
