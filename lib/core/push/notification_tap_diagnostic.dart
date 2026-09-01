/// A minimal, sanitized record of one notification-tap routing outcome —
/// safe to log. Carries only a fixed, closed-vocabulary [reason]; never
/// `device_id`, `event_id`, `call_id`, a payload, or a token.
final class NotificationTapDiagnostic {
  const NotificationTapDiagnostic._(this.reason);

  /// A tapped notification (call-mode or `NOTIFICATION_ONLY` — both share
  /// the same [RingCallIntent] payload shape) restored successfully and was
  /// handed to `RingCallNavigationCoordinator`.
  factory NotificationTapDiagnostic.callAccepted() =>
      const NotificationTapDiagnostic._('call_accepted');

  /// A tapped notification had a call payload's shape but failed to
  /// restore (expired, malformed, foreign version) — see
  /// `routeNotificationTap`'s safe-recovery path.
  factory NotificationTapDiagnostic.callRejected() =>
      const NotificationTapDiagnostic._('call_rejected');

  final String reason;

  /// A single-line, debug-only diagnostic string. Callers still must gate
  /// this behind `kDebugMode`/an equivalent flag.
  String toLogLine() => '[TAP][DEBUG-ONLY] $reason';
}
