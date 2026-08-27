import 'push_message.dart';

/// Narrow seam between the app and whatever push provider backs it.
///
/// Nothing outside `lib/core/push` should import `firebase_messaging`
/// directly — the real implementation ([FirebaseMessagingClient]) lives
/// behind this interface, and tests use a fake instead of talking to
/// Firebase.
abstract class PushMessagingClient {
  /// Current permission state, without prompting the user.
  Future<PushAuthorizationStatus> getAuthorizationStatus();

  /// Prompts the user for permission. Callers must check
  /// [getAuthorizationStatus] first and only call this when the status is
  /// [PushAuthorizationStatus.notDetermined].
  Future<PushAuthorizationStatus> requestPermission();

  /// The current FCM registration token, or null if unavailable.
  Future<String?> getToken();

  /// Emits a new token whenever FCM rotates it.
  Stream<String> get onTokenRefresh;

  /// Messages received while the app is in the foreground.
  Stream<PushMessage> get onForegroundMessage;

  /// Emitted when the user taps a notification that opened the app from
  /// the background.
  Stream<PushMessage> get onMessageOpenedApp;

  /// The message that opened the app from a fully terminated state, if any.
  Future<PushMessage?> getInitialMessage();
}
