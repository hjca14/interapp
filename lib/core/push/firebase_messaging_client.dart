import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_message.dart';
import 'push_messaging_client.dart';

/// [PushMessagingClient] backed by the real `firebase_messaging` plugin.
class FirebaseMessagingClient implements PushMessagingClient {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return _toPushStatus(settings.authorizationStatus);
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return _toPushStatus(settings.authorizationStatus);
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_toPushMessage);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_toPushMessage);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _toPushMessage(message);
  }

  static PushAuthorizationStatus _toPushStatus(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized => PushAuthorizationStatus.granted,
      AuthorizationStatus.denied => PushAuthorizationStatus.denied,
      AuthorizationStatus.notDetermined =>
        PushAuthorizationStatus.notDetermined,
      AuthorizationStatus.provisional => PushAuthorizationStatus.provisional,
      AuthorizationStatus.deniedPermanently =>
        PushAuthorizationStatus.deniedPermanently,
    };
  }

  static PushMessage _toPushMessage(RemoteMessage message) {
    return PushMessage(
      messageId: message.messageId,
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data,
    );
  }
}
