import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/full_screen_intent_access.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';

void main() {
  group('IncomingCallNotificationService.androidChannelFor', () {
    test('RING_ONLY selects the sound-enabled call channel', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.ringOnly,
      );

      expect(details.channelId, 'incoming_call');
      expect(details.playSound, isTrue);
    });

    test(
      'RING_AND_NOTIFICATION also selects the sound-enabled call channel',
      () {
        final details = IncomingCallNotificationService.androidChannelFor(
          RingPresentationIntent.ringAndNotification,
        );

        expect(details.channelId, 'incoming_call');
        expect(details.playSound, isTrue);
      },
    );

    test('NOTIFICATION_ONLY selects the silent channel', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(details.channelId, isNot('incoming_call'));
      expect(details.playSound, isFalse);
      expect(details.enableVibration, isFalse);
    });

    test('the call and silent channels are distinct Android channel ids', () {
      final call = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.ringOnly,
      );
      final silent = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(call.channelId, isNot(silent.channelId));
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

        expect(details.channelId, 'incoming_call');
        expect(details.category, AndroidNotificationCategory.call);
        expect(details.fullScreenIntent, isTrue);
        expect(details.importance, Importance.max);
        expect(details.priority, Priority.high);
        expect(details.playSound, isTrue);
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

    test('NOTIFICATION_ONLY never selects call category or full-screen', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
      );

      expect(details.category, isNot(AndroidNotificationCategory.call));
      expect(details.fullScreenIntent, isFalse);
    });
  });

  group('IncomingCallNotificationService.present', () {
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
      // manually so `_plugin.show()` reaches [notificationsChannel] instead
      // of throwing LateInitializationError.
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fullScreenAccessChannel, null);
    });

    RingDetectedEvent eventFor(RingPresentationIntent intent) =>
        RingDetectedEvent(
          eventId: 'evt-${'a' * 32}',
          deviceId: 'ib-${'b' * 32}',
          presentationIntent: intent,
          occurredAt: DateTime.utc(2026, 1, 1),
        );

    /// Registers a capturing handler for the notifications plugin's own
    /// channel and returns the arguments of its `show` call. Deliberately
    /// leaves [fullScreenAccessChannel] with no handler at all — the
    /// `MainActivity`-only MethodChannel [present] must not depend on — so a
    /// missing handler here stands in for `MainActivity`/the Activity not
    /// being alive, exactly the background/locked scenario this exists for.
    Future<Map<Object?, Object?>> capturePresentedShow(
      RingPresentationIntent intent, {
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

      await service.present(eventFor(intent));

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
            intent,
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
          intent,
          fullScreenIntentChecker: () async =>
              throw StateError('simulated MethodChannel failure'),
        );

        final platformSpecifics =
            args['platformSpecifics'] as Map<Object?, Object?>;
        expect(platformSpecifics['fullScreenIntent'], isTrue);
      });
    }

    test('NOTIFICATION_ONLY never presents with full-screen intent, and never '
        'consults the full-screen-access checker either', () async {
      final args = await capturePresentedShow(
        RingPresentationIntent.notificationOnly,
        fullScreenIntentChecker: () async {
          fail('present() must never consult the full-screen checker');
        },
      );

      final platformSpecifics =
          args['platformSpecifics'] as Map<Object?, Object?>;
      expect(platformSpecifics['fullScreenIntent'], isFalse);
      expect(platformSpecifics['category'], isNot('call'));
    });
  });
}
