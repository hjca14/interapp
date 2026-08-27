/// Platform-agnostic view of an inbound push notification.
///
/// Decoupled from `firebase_messaging`'s `RemoteMessage` so the rest of the
/// app depends only on this file, not on the Firebase plugin directly.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, dynamic> data;
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
