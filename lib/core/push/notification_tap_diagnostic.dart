/// A minimal, sanitized record of one notification-tap routing outcome —
/// safe to log. Carries only a fixed, closed-vocabulary [reason]; never
/// `device_id`, `event_id`, `call_id`, a payload, or a token.
final class NotificationTapDiagnostic {
  const NotificationTapDiagnostic._(this.reason);

  /// A tapped call notification restored successfully and was handed to the
  /// navigation coordinator.
  factory NotificationTapDiagnostic.callAccepted() =>
      const NotificationTapDiagnostic._('call_accepted');

  /// A tapped notification had a call payload's shape but failed to
  /// restore (expired, malformed, foreign version) — see
  /// `routeNotificationTap`'s safe-recovery path.
  factory NotificationTapDiagnostic.callRejected() =>
      const NotificationTapDiagnostic._('call_rejected');

  /// A tapped `NOTIFICATION_ONLY` notification restored successfully.
  factory NotificationTapDiagnostic.deviceNotificationAccepted() =>
      const NotificationTapDiagnostic._('device_notification_accepted');

  /// A device-event tap arrived before authentication was confirmed —
  /// preserved as a pending intent rather than navigated immediately.
  factory NotificationTapDiagnostic.pendingAwaitingAuthentication() =>
      const NotificationTapDiagnostic._('pending_awaiting_authentication');

  /// A pending device-event intent's device failed authorization once
  /// authentication resolved — never navigated.
  factory NotificationTapDiagnostic.deviceNotAuthorized() =>
      const NotificationTapDiagnostic._('device_not_authorized');

  /// A pending device-event intent was authorized and its destination
  /// route was actually opened.
  factory NotificationTapDiagnostic.destinationOpened() =>
      const NotificationTapDiagnostic._('destination_opened');

  final String reason;

  /// A single-line, debug-only diagnostic string. Callers still must gate
  /// this behind `kDebugMode`/an equivalent flag.
  String toLogLine() => '[TAP][DEBUG-ONLY] $reason';
}
