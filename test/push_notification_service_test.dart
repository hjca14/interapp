import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/push_message.dart';
import 'package:interapp/core/push/push_messaging_client.dart';
import 'package:interapp/core/push/push_notification_service.dart';

class FakePushMessagingClient implements PushMessagingClient {
  PushAuthorizationStatus authorizationStatus =
      PushAuthorizationStatus.notDetermined;
  PushAuthorizationStatus requestPermissionResult =
      PushAuthorizationStatus.granted;
  int requestPermissionCallCount = 0;

  String? token = 'initial-token';
  Object? getAuthorizationStatusError;
  Object? getTokenError;
  PushMessage? initialMessage;
  Object? getInitialMessageError;

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundController = StreamController<PushMessage>.broadcast();
  final _openedAppController = StreamController<PushMessage>.broadcast();

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() async {
    if (getAuthorizationStatusError != null) {
      throw getAuthorizationStatusError!;
    }
    return authorizationStatus;
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    requestPermissionCallCount++;
    return requestPermissionResult;
  }

  @override
  Future<String?> getToken() async {
    if (getTokenError != null) {
      throw getTokenError!;
    }
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => _foregroundController.stream;

  @override
  Stream<PushMessage> get onMessageOpenedApp => _openedAppController.stream;

  @override
  Future<PushMessage?> getInitialMessage() async {
    if (getInitialMessageError != null) {
      throw getInitialMessageError!;
    }
    return initialMessage;
  }

  void emitTokenRefresh(String newToken) =>
      _tokenRefreshController.add(newToken);

  void emitForegroundMessage(PushMessage message) =>
      _foregroundController.add(message);

  void emitMessageOpenedApp(PushMessage message) =>
      _openedAppController.add(message);
}

void main() {
  late FakePushMessagingClient client;

  setUp(() {
    client = FakePushMessagingClient();
  });

  test('requests permission when status is not yet determined', () async {
    client.authorizationStatus = PushAuthorizationStatus.notDetermined;
    client.requestPermissionResult = PushAuthorizationStatus.granted;
    final service = PushNotificationService(client, debugMode: false);

    await service.initialize();

    expect(client.requestPermissionCallCount, 1);
    expect(service.authorizationStatus, PushAuthorizationStatus.granted);
  });

  test('does not re-request permission when already granted', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    final service = PushNotificationService(client, debugMode: false);

    await service.initialize();

    expect(client.requestPermissionCallCount, 0);
    expect(service.authorizationStatus, PushAuthorizationStatus.granted);
  });

  test('does not re-request permission when already denied', () async {
    client.authorizationStatus = PushAuthorizationStatus.denied;
    final service = PushNotificationService(client, debugMode: false);

    await service.initialize();

    expect(client.requestPermissionCallCount, 0);
    expect(service.authorizationStatus, PushAuthorizationStatus.denied);
  });

  test('a denied permission is not treated as a fatal error', () async {
    client.authorizationStatus = PushAuthorizationStatus.denied;
    final service = PushNotificationService(client, debugMode: false);

    await expectLater(service.initialize(), completes);
  });

  test('obtains the initial token', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.token = 'token-abc';
    final service = PushNotificationService(client, debugMode: true);

    await service.initialize();

    expect(service.debugOnlyToken, 'token-abc');
  });

  test('handles a missing token without failing', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.token = null;
    final service = PushNotificationService(client, debugMode: true);

    await expectLater(service.initialize(), completes);
    expect(service.debugOnlyToken, isNull);
  });

  test('updates in-memory state when the token refreshes', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.token = 'old-token';
    final service = PushNotificationService(client, debugMode: true);
    await service.initialize();

    client.emitTokenRefresh('new-token');
    await pumpEventQueue();

    expect(service.debugOnlyToken, 'new-token');
  });

  test('never exposes the token when not in debug mode', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.token = 'secret-ish-token';
    final service = PushNotificationService(client, debugMode: false);
    await service.initialize();

    expect(service.debugOnlyToken, isNull);
  });

  test('forwards foreground messages', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    final service = PushNotificationService(client, debugMode: false);
    await service.initialize();

    final received = <PushMessage>[];
    final subscription = service.onForegroundMessage.listen(received.add);
    client.emitForegroundMessage(const PushMessage(title: 'Oi'));
    await pumpEventQueue();
    await subscription.cancel();

    expect(received, hasLength(1));
    expect(received.single.title, 'Oi');
  });

  test('forwards the notification-tap-opened-app event', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    final service = PushNotificationService(client, debugMode: false);
    await service.initialize();

    final received = <PushMessage>[];
    final subscription = service.onMessageOpenedApp.listen(received.add);
    client.emitMessageOpenedApp(const PushMessage(title: 'Toque'));
    await pumpEventQueue();
    await subscription.cancel();

    expect(received, hasLength(1));
    expect(received.single.title, 'Toque');
  });

  test('returns the message that opened the app from a cold start', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.initialMessage = const PushMessage(title: 'Inicial');
    final service = PushNotificationService(client, debugMode: false);
    await service.initialize();

    final message = await service.getInitialMessage();

    expect(message?.title, 'Inicial');
  });

  test('a bootstrap failure does not throw and the app can proceed', () async {
    client.getAuthorizationStatusError = Exception('boom');
    final service = PushNotificationService(client, debugMode: false);

    await expectLater(service.initialize(), completes);
    expect(service.authorizationStatus, isNull);
  });

  test('a token failure does not throw', () async {
    client.authorizationStatus = PushAuthorizationStatus.granted;
    client.getTokenError = Exception('boom');
    final service = PushNotificationService(client, debugMode: false);

    await expectLater(service.initialize(), completes);
  });

  test('getInitialMessage never throws a raw exception', () async {
    client.getInitialMessageError = Exception('boom');
    final service = PushNotificationService(client, debugMode: false);

    final message = await service.getInitialMessage();

    expect(message, isNull);
  });
}
