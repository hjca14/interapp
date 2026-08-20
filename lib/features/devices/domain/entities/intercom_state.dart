/// The interfone's operating state as reported in the device's Device
/// Shadow (`intercom_state`), per `docs/communication-protocol.md` §22.1.
///
/// The protocol defines exactly five known values ([idle], [ringing],
/// [offHook], [inCall], [error]). Still modeled as an open value wrapper
/// rather than a closed `enum`, because §22.1 requires that a value outside
/// this set become a safe unknown state — preserving the raw string for
/// diagnostics — instead of throwing. A closed `enum`'s `fromWireValue`
/// would have to drop the raw string on an unrecognized value; this keeps
/// it.
class IntercomState {
  const IntercomState._(this.raw);

  /// No state has been reported yet. An app-local sentinel — not a value
  /// the firmware/backend ever sends.
  static const unreported = IntercomState._(null);

  static const idle = IntercomState._('IDLE');
  static const ringing = IntercomState._('RINGING');
  static const offHook = IntercomState._('OFF_HOOK');
  static const inCall = IntercomState._('IN_CALL');
  static const error = IntercomState._('ERROR');

  static const _known = [idle, ringing, offHook, inCall, error];

  factory IntercomState.fromRaw(String? raw) {
    if (raw == null) {
      return unreported;
    }
    for (final state in _known) {
      if (state.raw == raw) {
        return state;
      }
    }
    return IntercomState._(raw);
  }

  /// The exact string as reported by the backend, or `null` for
  /// [unreported].
  final String? raw;

  /// Whether [raw] is one of the five states §22.1 defines. `false` for
  /// [unreported] and for any value this app doesn't recognize yet — [raw]
  /// still preserves the original string in that case.
  bool get isKnown => _known.any((state) => state.raw == raw);

  bool get isReported => raw != null;

  @override
  bool operator ==(Object other) => other is IntercomState && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => raw ?? 'unreported';
}
