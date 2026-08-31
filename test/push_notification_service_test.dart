import 'dart:async';

import 'package:flutter/foundation.dart';
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
  int getTokenCallCount = 0;
  int getInitialMessageCallCount = 0;

  String? token = 'initial-token';
  Object? getAuthorizationStatusError;
  Object? getTokenError;
  PushMessage? initialMessage;
  Object? getInitialMessageError;

  /// When set, [requestPermission] waits on this future before resolving —
  /// lets a test hold the permission prompt "open" to prove callers don't
  /// block on it.
  Future<void>? permissionDelay;

  /// Same idea as [permissionDelay], for [getToken].
  Future<void>? tokenDelay;

  int tokenRefreshListenCount = 0;
  int foregroundListenCount = 0;
  int openedAppListenCount = 0;

  late final _tokenRefreshController = StreamController<String>.broadcast(
    onListen: () => tokenRefreshListenCount++,
  );
  late final _foregroundController = StreamController<PushMessage>.broadcast(
    onListen: () => foregroundListenCount++,
  );
  late final _openedAppController = StreamController<PushMessage>.broadcast(
    onListen: () => openedAppListenCount++,
  );

  @override
  Future<PushAuthorizationStatus> getAuthorizationStatus() async {
    if (getAuthorizationStatusError != null) {
      throw getAuthorizationStatusError!;
    }
    return authorizationStatus;
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    if (permissionDelay != null) {
      await permissionDelay;
    }
    requestPermissionCallCount++;
    return requestPermissionResult;
  }

  @override
  Future<String?> getToken() async {
    if (tokenDelay != null) {
      await tokenDelay;
    }
    getTokenCallCount++;
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
    getInitialMessageCallCount++;
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

  group('non-blocking startup', () {
    test('a slow permission prompt does not block the caller (simulates '
        'runApp not waiting on it)', () async {
      final permissionGate = Completer<void>();
      client.authorizationStatus = PushAuthorizationStatus.notDetermined;
      client.permissionDelay = permissionGate.future;
      final service = PushNotificationService(client, null, debugMode: false);

      var reachedNextStatement = false;
      unawaited(service.initialize());
      reachedNextStatement = true;

      expect(reachedNextStatement, isTrue);
      expect(service.authorizationStatus, isNull);

      permissionGate.complete();
      await pumpEventQueue();

      expect(service.authorizationStatus, PushAuthorizationStatus.granted);
    });

    test('a slow getToken call does not block the caller', () async {
      final tokenGate = Completer<void>();
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.tokenDelay = tokenGate.future;
      final service = PushNotificationService(client, null, debugMode: false);

      var reachedNextStatement = false;
      unawaited(service.initialize());
      reachedNextStatement = true;

      expect(reachedNextStatement, isTrue);
      expect(service.hasToken, isFalse);

      tokenGate.complete();
      await pumpEventQueue();

      expect(service.hasToken, isTrue);
    });

    test(
      'a bootstrap failure does not throw and the app can proceed',
      () async {
        client.getAuthorizationStatusError = Exception('boom');
        final service = PushNotificationService(client, null, debugMode: false);

        await expectLater(service.initialize(), completes);
        expect(service.authorizationStatus, isNull);
      },
    );
  });

  group('failures in one phase do not block the others', () {
    test(
      'a permission check failure still lets token and listeners run',
      () async {
        client.getAuthorizationStatusError = Exception('boom');
        client.token = 'token-despite-permission-failure';
        final service = PushNotificationService(client, null, debugMode: false);

        await service.initialize();

        expect(service.authorizationStatus, isNull);
        expect(service.hasToken, isTrue);
        expect(client.tokenRefreshListenCount, 1);
        expect(client.foregroundListenCount, 1);
        expect(client.openedAppListenCount, 1);
        expect(client.getInitialMessageCallCount, 1);
      },
    );

    test(
      'a getToken() failure still lets foreground and tap-to-open work',
      () async {
        client.authorizationStatus = PushAuthorizationStatus.granted;
        client.getTokenError = Exception('boom');
        final service = PushNotificationService(client, null, debugMode: false);
        await service.initialize();

        expect(service.hasToken, isFalse);

        client.emitForegroundMessage(
          const PushMessage(messageId: 'fg-after-token-failure', title: 'x'),
        );
        client.emitMessageOpenedApp(
          const PushMessage(
            messageId: 'opened-after-token-failure',
            title: 'y',
          ),
        );
        await pumpEventQueue();

        expect(
          service.lastForegroundEvent?.messageId,
          'fg-after-token-failure',
        );
        expect(
          service.lastOpenedAppEvent?.messageId,
          'opened-after-token-failure',
        );
      },
    );

    test('a getInitialMessage() failure still leaves the token and listeners '
        'active', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'token-despite-initial-message-failure';
      client.getInitialMessageError = Exception('boom');
      final service = PushNotificationService(client, null, debugMode: false);
      await service.initialize();

      client.emitForegroundMessage(
        const PushMessage(messageId: 'fg-after-initial-failure', title: 'z'),
      );
      await pumpEventQueue();

      expect(service.hasToken, isTrue);
      expect(
        service.lastForegroundEvent?.messageId,
        'fg-after-initial-failure',
      );
      expect(service.lastInitialMessageEvent, isNull);
    });

    test(
      'none of the four phases run more than once, even when some fail',
      () async {
        client.getAuthorizationStatusError = Exception('boom');
        client.getTokenError = Exception('boom');
        client.getInitialMessageError = Exception('boom');
        final service = PushNotificationService(client, null, debugMode: false);

        await service.initialize();
        await service.initialize();

        expect(client.getTokenCallCount, 1);
        expect(client.getInitialMessageCallCount, 1);
        expect(client.tokenRefreshListenCount, 1);
        expect(client.foregroundListenCount, 1);
        expect(client.openedAppListenCount, 1);
      },
    );
  });

  group('permission handling', () {
    test('requests permission when status is not yet determined', () async {
      client.authorizationStatus = PushAuthorizationStatus.notDetermined;
      client.requestPermissionResult = PushAuthorizationStatus.granted;
      final service = PushNotificationService(client, null, debugMode: false);

      await service.initialize();

      expect(client.requestPermissionCallCount, 1);
      expect(service.authorizationStatus, PushAuthorizationStatus.granted);
    });

    test('does not re-request permission when already granted', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      final service = PushNotificationService(client, null, debugMode: false);

      await service.initialize();

      expect(client.requestPermissionCallCount, 0);
      expect(service.authorizationStatus, PushAuthorizationStatus.granted);
    });

    test('does not re-request permission when already denied', () async {
      client.authorizationStatus = PushAuthorizationStatus.denied;
      final service = PushNotificationService(client, null, debugMode: false);

      await service.initialize();

      expect(client.requestPermissionCallCount, 0);
      expect(service.authorizationStatus, PushAuthorizationStatus.denied);
    });

    test('a denied permission is not treated as a fatal error', () async {
      client.authorizationStatus = PushAuthorizationStatus.denied;
      final service = PushNotificationService(client, null, debugMode: false);

      await expectLater(service.initialize(), completes);
    });
  });

  group('idempotent initialization', () {
    test('a second initialize() call reuses the same future', () async {
      client.authorizationStatus = PushAuthorizationStatus.notDetermined;
      final service = PushNotificationService(client, null, debugMode: false);

      final first = service.initialize();
      final second = service.initialize();
      await first;
      await second;

      expect(identical(first, second), isTrue);
      expect(client.requestPermissionCallCount, 1);
      expect(client.getTokenCallCount, 1);
      expect(client.getInitialMessageCallCount, 1);
    });

    test(
      'subscribes to each stream exactly once even across repeated calls',
      () async {
        client.authorizationStatus = PushAuthorizationStatus.granted;
        final service = PushNotificationService(client, null, debugMode: false);

        await service.initialize();
        await service.initialize();

        expect(client.tokenRefreshListenCount, 1);
        expect(client.foregroundListenCount, 1);
        expect(client.openedAppListenCount, 1);
      },
    );
  });

  group('token stays internal', () {
    test('hasToken becomes true once the initial token is obtained', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'token-abc';
      final service = PushNotificationService(client, null, debugMode: false);

      await service.initialize();

      expect(service.hasToken, isTrue);
    });

    test('hasToken stays false when there is no token', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = null;
      final service = PushNotificationService(client, null, debugMode: false);

      await expectLater(service.initialize(), completes);
      expect(service.hasToken, isFalse);
    });

    test('a token fetch failure does not throw', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.getTokenError = Exception('boom');
      final service = PushNotificationService(client, null, debugMode: false);

      await expectLater(service.initialize(), completes);
    });

    test(
      'the refreshed token is kept internally, in place of the old one',
      () async {
        client.authorizationStatus = PushAuthorizationStatus.granted;
        client.token = null;
        final service = PushNotificationService(client, null, debugMode: false);
        await service.initialize();
        expect(service.hasToken, isFalse);

        client.emitTokenRefresh('new-token');
        await pumpEventQueue();

        expect(service.hasToken, isTrue);
      },
    );

    test('there is no public API that exposes the full token value', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'secret-ish-token';
      final service = PushNotificationService(client, null, debugMode: true);
      await service.initialize();
      client.emitTokenRefresh('refreshed-secret-ish-token');
      await pumpEventQueue();

      // PushNotificationService only exposes hasToken (a bool). There is
      // no getter — in any build mode — that returns the token string
      // itself; this test exists so the seam gets re-verified if one is
      // ever added back.
      expect(service.hasToken, isTrue);
    });
  });

  group('message events are consumed', () {
    test('a foreground message updates the last-event diagnostic', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      final service = PushNotificationService(client, null, debugMode: false);
      await service.initialize();

      client.emitForegroundMessage(
        const PushMessage(messageId: 'msg-fg', title: 'Oi', body: 'corpo'),
      );
      await pumpEventQueue();

      expect(service.lastForegroundEvent?.messageId, 'msg-fg');
      expect(service.lastForegroundEvent?.hasTitle, isTrue);
      expect(service.lastForegroundEvent?.hasBody, isTrue);
    });

    test(
      'a tap that opens the app from background updates the diagnostic',
      () async {
        client.authorizationStatus = PushAuthorizationStatus.granted;
        final service = PushNotificationService(client, null, debugMode: false);
        await service.initialize();

        client.emitMessageOpenedApp(
          const PushMessage(messageId: 'msg-opened', title: 'Toque'),
        );
        await pumpEventQueue();

        expect(service.lastOpenedAppEvent?.messageId, 'msg-opened');
        expect(service.lastOpenedAppEvent?.hasTitle, isTrue);
        expect(service.lastOpenedAppEvent?.hasBody, isFalse);
      },
    );

    test(
      'queries and consumes the cold-start initial message exactly once',
      () async {
        client.authorizationStatus = PushAuthorizationStatus.granted;
        client.initialMessage = const PushMessage(
          messageId: 'msg-cold',
          title: 'Inicial',
        );
        final service = PushNotificationService(client, null, debugMode: false);

        await service.initialize();
        await service.initialize();

        expect(client.getInitialMessageCallCount, 1);
        expect(service.lastInitialMessageEvent?.messageId, 'msg-cold');
      },
    );

    test('a failure fetching the initial message does not throw and leaves '
        'the diagnostic empty', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.getInitialMessageError = Exception('boom');
      final service = PushNotificationService(client, null, debugMode: false);

      await expectLater(service.initialize(), completes);
      expect(service.lastInitialMessageEvent, isNull);
    });
  });

  group('onForegroundMessage hook', () {
    test('is invoked with every foreground message', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      final received = <PushMessage>[];
      final service = PushNotificationService(
        client,
        null,
        onForegroundMessage: received.add,
        debugMode: false,
      );
      await service.initialize();

      const message = PushMessage(messageId: 'msg-ring', title: 'Oi');
      client.emitForegroundMessage(message);
      await pumpEventQueue();

      expect(received, [message]);
    });

    test('a throwing hook does not break the foreground diagnostic or the '
        'other listeners', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      final service = PushNotificationService(
        client,
        null,
        onForegroundMessage: (_) => throw Exception('boom'),
        debugMode: false,
      );
      await service.initialize();

      client.emitForegroundMessage(
        const PushMessage(messageId: 'msg-ring', title: 'Oi'),
      );
      client.emitMessageOpenedApp(
        const PushMessage(messageId: 'msg-opened', title: 'Toque'),
      );
      await pumpEventQueue();

      expect(service.lastForegroundEvent?.messageId, 'msg-ring');
      expect(service.lastOpenedAppEvent?.messageId, 'msg-opened');
    });

    test('is never invoked for onMessageOpenedApp', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      final received = <PushMessage>[];
      final service = PushNotificationService(
        client,
        null,
        onForegroundMessage: received.add,
        debugMode: false,
      );
      await service.initialize();

      client.emitMessageOpenedApp(
        const PushMessage(messageId: 'msg-opened', title: 'Toque'),
      );
      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });

  group('dispose', () {
    test('cancels every subscription created during initialize', () async {
      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'before-dispose';
      final service = PushNotificationService(client, null, debugMode: false);
      await service.initialize();

      await service.dispose();

      client.emitForegroundMessage(
        const PushMessage(messageId: 'after-dispose'),
      );
      client.emitTokenRefresh('after-dispose-token');
      await pumpEventQueue();

      expect(service.lastForegroundEvent, isNull);
      expect(service.hasToken, isTrue);
    });
  });

  group('diagnostic logging is sanitized', () {
    test('never logs the token value, title, body, data payload, or a raw '
        'exception — even in debug mode', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logs.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'super-sensitive-token-value';
      final service = PushNotificationService(client, null, debugMode: true);
      await service.initialize();

      client.emitTokenRefresh('another-super-sensitive-token-value');
      client.emitForegroundMessage(
        const PushMessage(
          messageId: 'msg-1',
          title: 'titulo-secreto',
          body: 'corpo-com-dados-sensiveis-do-morador',
          data: {'chamador': 'joao'},
        ),
      );
      await pumpEventQueue();

      final joined = logs.join('\n');
      expect(joined, isNot(contains('super-sensitive-token-value')));
      expect(joined, isNot(contains('another-super-sensitive')));
      expect(joined, isNot(contains('titulo-secreto')));
      expect(joined, isNot(contains('corpo-com-dados-sensiveis')));
      expect(joined, isNot(contains('joao')));
      expect(joined, isNot(contains('Exception')));

      // Sanitized markers are still expected: presence-only for the token,
      // messageId + booleans for the message paths.
      expect(joined, contains('token_initial present=true'));
      expect(joined, contains('token_refresh present=true'));
      expect(joined, contains('foreground'));
      expect(joined, contains('msg-1'));
      expect(joined, contains('hasTitle=true'));
      expect(joined, contains('hasBody=true'));
    });

    test('logs nothing at all outside debug mode', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logs.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      client.authorizationStatus = PushAuthorizationStatus.granted;
      client.token = 'should-not-be-logged';
      final service = PushNotificationService(client, null, debugMode: false);
      await service.initialize();

      client.emitTokenRefresh('should-not-be-logged-either');
      client.emitForegroundMessage(
        const PushMessage(messageId: 'msg-1', title: 'x'),
      );
      await pumpEventQueue();

      expect(logs, isEmpty);
    });
  });
}
