/// Platform-agnostic view of an inbound push notification.
///
/// Decoupled from `firebase_messaging`'s `RemoteMessage` so the rest of the
/// app depends only on this file, not on the Firebase plugin directly. Never
/// leaves the `lib/core/push` adapter boundary as a stored value — only the
/// [PushEventDiagnostic] derived from it does.
class PushMessage {
  const PushMessage({
    this.messageId,
    this.title,
    this.body,
    this.data = const {},
  });

  final String? messageId;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
}

/// A minimal, sanitized record of one push event — never the title, body,
/// or `data` payload, so it is safe to log or keep in memory. Enough to
/// confirm during manual testing that a given path (foreground, tap-to-open,
/// cold start) actually fired.
class PushEventDiagnostic {
  const PushEventDiagnostic({
    required this.messageId,
    required this.hasTitle,
    required this.hasBody,
  });

  factory PushEventDiagnostic.fromMessage(PushMessage message) {
    return PushEventDiagnostic(
      messageId: message.messageId,
      hasTitle: message.title != null,
      hasBody: message.body != null,
    );
  }

  final String? messageId;
  final bool hasTitle;
  final bool hasBody;
}

/// Mirrors `firebase_messaging`'s `AuthorizationStatus` without exposing the
/// plugin type outside [PushMessagingClient] implementations.
enum PushAuthorizationStatus {
  granted,
  denied,

  /// Denied on Android 13+ such that the OS will not show another prompt;
  /// the user must enable notifications from system settings instead.
  deniedPermanently,
  notDetermined,
  provisional,
}
