import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/device_event_notification_intent.dart';
import 'package:interapp/core/push/full_screen_intent_access.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';

void main() {
  group('IncomingCallNotificationService.androidChannelFor', () {
    test('RING_ONLY selects the call channel', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.ringOnly,
      );

      expect(details.channelId, 'incoming_call_v2');
      expect(details.playSound, isTrue);
    });

    test('RING_AND_NOTIFICATION (legacy) also selects the call channel', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.ringAndNotification,
      );

      expect(details.channelId, 'incoming_call_v2');
      expect(details.playSound, isTrue);
    });

    test(
      'NOTIFICATION_ONLY selects the audible device-notification channel',
      () {
        final details = IncomingCallNotificationService.androidChannelFor(
          RingPresentationIntent.notificationOnly,
        );

        expect(details.channelId, 'device_notification_v1');
        expect(details.channelId, isNot('incoming_call_v2'));
        expect(
          details.playSound,
          isTrue,
          reason: 'a normal, audible notification — never forced silent',
        );
      },
    );

    test('the call and notification channels are distinct Android channel '
        'ids', () {
      final call = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.ringOnly,
      );
      final notification = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(call.channelId, isNot(notification.channelId));
    });

    for (final intent in [
      RingPresentationIntent.ringOnly,
      RingPresentationIntent.ringAndNotification,
    ]) {
      test('$intent always selects call category and full-screen intent — '
          'unconditionally, not gated by any OS access check. Android '
          'itself degrades this to a functional heads-up alert when '
          '`USE_FULL_SCREEN_INTENT` access is not held', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(details.channelId, 'incoming_call_v2');
        expect(details.category, AndroidNotificationCategory.call);
        expect(details.fullScreenIntent, isTrue);
        expect(details.importance, Importance.max);
        expect(details.priority, Priority.high);
        expect(details.playSound, isTrue);
      });

      test('$intent is ongoing (cannot be swiped away by accident), never '
          'auto-cancels on tap, and keeps ringing until explicitly '
          'canceled', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(details.ongoing, isTrue);
        expect(details.autoCancel, isFalse);
      });

      test('$intent sets the insistent flag so the ringtone repeats '
          'continuously instead of alerting once', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        const flagInsistent = 0x00000004;
        expect(details.additionalFlags, isNotNull);
        expect(details.additionalFlags!.contains(flagInsistent), isTrue);
      });

      test('$intent uses ringtone audio attributes', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(
          details.audioAttributesUsage,
          AudioAttributesUsage.notificationRingtone,
        );
      });

      test('$intent auto-cancels itself after 60s at the OS level — the '
          'same local ring-timeout duration used for navigation, enforced '
          'even if the app process is not alive to run a Dart timer', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(details.timeoutAfter, 60000);
      });

      test('$intent never attaches a notification action — Atender/Dispensar '
          'live only in IncomingCallPage, reached through the shared '
          'coordinator, never a background-isolate action shortcut', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(details.actions, anyOf(isNull, isEmpty));
      });
    }

    test('NOTIFICATION_ONLY never selects call category, full-screen, '
        'ongoing, or the insistent flag', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(details.category, isNot(AndroidNotificationCategory.call));
      expect(details.fullScreenIntent, isFalse);
      expect(details.ongoing, isFalse);
      expect(details.additionalFlags, anyOf(isNull, isEmpty));
    });

    test('NOTIFICATION_ONLY is auto-cancelable like an ordinary notification — '
        'unlike the call channel, which is never auto-canceled by a tap', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(details.autoCancel, isTrue);
    });
  });

  group('IncomingCallNotificationService.present/endCall', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const fullScreenAccessChannel = MethodChannel(
      'interapp/full_screen_intent',
    );

    setUp(() {
      // The plugin's platform-interface instance is normally registered by
      // GeneratedPluginRegistrant at app startup; tests must register it
      // manually so `_plugin.show()`/`.cancel()` reach [notificationsChannel]
      // instead of throwing LateInitializationError.
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fullScreenAccessChannel, null);
    });

    RingDetectedEvent eventFor(
      RingPresentationIntent intent, {
      String callId = 'call-cccccccccccccccccccccccccccccccc',
    }) => RingDetectedEvent(
      eventId: 'evt-${'a' * 32}',
      deviceId: 'ib-${'b' * 32}',
      presentationIntent: intent,
      occurredAt: DateTime.utc(2026, 1, 1),
      callId: callId,
    );

    /// Registers a capturing handler for the notifications plugin's own
    /// channel and returns the arguments of its `show` call. Deliberately
    /// leaves [fullScreenAccessChannel] with no handler at all — the
    /// `MainActivity`-only MethodChannel [present] must not depend on — so a
    /// missing handler here stands in for `MainActivity`/the Activity not
    /// being alive, exactly the background/locked scenario this exists for.
    Future<Map<Object?, Object?>> capturePresentedShow(
      RingDetectedEvent event, {
      required FullScreenIntentChecker fullScreenIntentChecker,
    }) async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'show') captured = call;
            return null;
          });
      final service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
        fullScreenIntentChecker: fullScreenIntentChecker,
      );

      await service.present(event);

      expect(captured, isNotNull, reason: 'show was never invoked');
      return captured!.arguments as Map<Object?, Object?>;
    }

    for (final intent in [
      RingPresentationIntent.ringOnly,
      RingPresentationIntent.ringAndNotification,
    ]) {
      test(
        '$intent presents with full-screen intent with no full-screen-access '
        'MethodChannel handler registered at all — proving it does not '
        'depend on MainActivity/an Activity being alive',
        () async {
          final args = await capturePresentedShow(
            eventFor(intent),
            fullScreenIntentChecker: () async {
              fail('present() must never consult the full-screen checker');
            },
          );

          final platformSpecifics =
              args['platformSpecifics'] as Map<Object?, Object?>;
          expect(platformSpecifics['fullScreenIntent'], isTrue);
          expect(platformSpecifics['category'], 'call');
        },
      );

      test('$intent presents with full-screen intent even when the '
          'full-screen-access checker throws — its failure never alters the '
          'push presentation', () async {
        final args = await capturePresentedShow(
          eventFor(intent),
          fullScreenIntentChecker: () async =>
              throw StateError('simulated MethodChannel failure'),
        );

        final platformSpecifics =
            args['platformSpecifics'] as Map<Object?, Object?>;
        expect(platformSpecifics['fullScreenIntent'], isTrue);
      });

      test('$intent is id\'d by call_id, so a repeated RING_DETECTED for '
          'the same call reuses the same notification id', () async {
        final args = await capturePresentedShow(
          eventFor(intent, callId: 'call-${'d' * 32}'),
          fullScreenIntentChecker: () async => false,
        );

        expect(args['id'], ringNotificationId('call-${'d' * 32}'));
      });

      test('$intent attaches a RingCallIntent payload restorable by '
          'RingCallIntent.tryRestore', () async {
        final args = await capturePresentedShow(
          eventFor(intent),
          fullScreenIntentChecker: () async => false,
        );

        final restored = RingCallIntent.tryRestore(
          args['payload'] as String?,
          now: DateTime.utc(2026, 1, 1),
        );
        expect(restored, isNotNull);
        expect(restored!.callId, 'call-${'c' * 32}');
      });
    }

    test('a call-mode present() notifies onCallPresented — production wiring '
        'uses this to open IncomingCallPage directly when InterBridge is '
        'already in foreground, without waiting for a tap or Android\'s own '
        'full-screen-intent decision', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (_) async => null);
      RingDetectedEvent? presented;
      final service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
        onCallPresented: (event) => presented = event,
      );

      await service.present(eventFor(RingPresentationIntent.ringOnly));

      expect(presented?.callId, 'call-${'c' * 32}');
    });

    test(
      'NOTIFICATION_ONLY present() never notifies onCallPresented — it is '
      'not a call, so it must never jump straight to IncomingCallPage',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(notificationsChannel, (_) async => null);
        final service = IncomingCallNotificationService(
          FlutterLocalNotificationsPlugin(),
          onCallPresented: (event) =>
              fail('NOTIFICATION_ONLY must never call onCallPresented'),
        );

        await service.present(
          eventFor(RingPresentationIntent.notificationOnly),
        );
      },
    );

    test('NOTIFICATION_ONLY never presents with full-screen intent, and never '
        'consults the full-screen-access checker either', () async {
      final args = await capturePresentedShow(
        eventFor(RingPresentationIntent.notificationOnly),
        fullScreenIntentChecker: () async {
          fail('present() must never consult the full-screen checker');
        },
      );

      final platformSpecifics =
          args['platformSpecifics'] as Map<Object?, Object?>;
      expect(platformSpecifics['fullScreenIntent'], isFalse);
      expect(platformSpecifics['category'], isNot('call'));
    });

    test('NOTIFICATION_ONLY attaches a DeviceEventNotificationIntent payload, '
        'never a RingCallIntent — tapping it must open a device destination, '
        'not IncomingCallPage', () async {
      final args = await capturePresentedShow(
        eventFor(RingPresentationIntent.notificationOnly),
        fullScreenIntentChecker: () async => false,
      );

      final payload = args['payload'] as String?;
      expect(RingCallIntent.tryRestore(payload), isNull);
      final deviceEvent = DeviceEventNotificationIntent.tryRestore(payload);
      expect(deviceEvent, isNotNull);
      expect(deviceEvent!.deviceId, 'ib-${'b' * 32}');
    });

    test('endCall cancels the notification for that call_id and reports '
        'onCallEnded', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'cancel') captured = call;
            return null;
          });
      String? endedCallId;
      final service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
        onCallEnded: (callId) => endedCallId = callId,
      );

      await service.endCall(
        RingEndedEvent(
          eventId: 'evt-${'e' * 32}',
          callId: 'call-${'c' * 32}',
          deviceId: 'ib-${'b' * 32}',
          occurredAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(captured, isNotNull, reason: 'cancel was never invoked');
      final args = captured!.arguments as Map<Object?, Object?>;
      expect(args['id'], ringNotificationId('call-${'c' * 32}'));
      expect(endedCallId, 'call-${'c' * 32}');
    });

    test('cancelNotificationById cancels exactly the given OS id, never a '
        'value recomputed from any call_id/payload — used by the safe-'
        'recovery path for a tapped call notification whose payload failed '
        'to restore', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'cancel') captured = call;
            return null;
          });
      final service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
      );

      await service.cancelNotificationById(4242);

      expect(captured, isNotNull, reason: 'cancel was never invoked');
      final args = captured!.arguments as Map<Object?, Object?>;
      expect(args['id'], 4242);
    });

    test('onDidReceiveNotificationResponse forwards both the payload and the '
        "response's own notification id to onRingNotificationTap", () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'requestNotificationsPermission') {
              return true;
            }
            return null;
          });
      String? capturedPayload;
      int? capturedId;
      final service = IncomingCallNotificationService(
        FlutterLocalNotificationsPlugin(),
        onRingNotificationTap: (payload, notificationId) {
          capturedPayload = payload;
          capturedId = notificationId;
        },
      );
      await service.initialize();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            notificationsChannel.name,
            notificationsChannel.codec.encodeMethodCall(
              const MethodCall('didReceiveNotificationResponse', {
                'notificationResponseType': 0,
                'notificationId': 4242,
                'payload': 'some-payload',
              }),
            ),
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);

      expect(capturedPayload, 'some-payload');
      expect(capturedId, 4242);
    });
  });
}
