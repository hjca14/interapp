import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
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
      test('$intent selects call/full-screen presentation when access is '
          'permitted', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
          fullScreenAllowed: true,
        );

        expect(details.channelId, 'incoming_call');
        expect(details.category, AndroidNotificationCategory.call);
        expect(details.fullScreenIntent, isTrue);
      });

      test('$intent falls back to a functional heads-up notification when '
          'full-screen access is denied', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
          fullScreenAllowed: false,
        );

        // Same channel, same importance/priority/sound — still a fully
        // working heads-up alert, just never launching over the lock
        // screen on its own.
        expect(details.channelId, 'incoming_call');
        expect(details.importance, Importance.max);
        expect(details.priority, Priority.high);
        expect(details.playSound, isTrue);
        expect(details.fullScreenIntent, isFalse);
      });

      test('$intent defaults to no full-screen when unspecified', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
        );

        expect(details.fullScreenIntent, isFalse);
      });

      test('$intent never attaches a notification action — Atender/Dispensar '
          'live only in IncomingCallPage, reached through the shared '
          'coordinator, never a background-isolate action shortcut', () {
        final details = IncomingCallNotificationService.androidChannelFor(
          intent,
          fullScreenAllowed: true,
        );

        expect(details.actions, anyOf(isNull, isEmpty));
      });
    }

    test('NOTIFICATION_ONLY never selects call category or full-screen, '
        'even when the OS reports full-screen access as permitted', () {
      final details = IncomingCallNotificationService.androidChannelFor(
        RingPresentationIntent.notificationOnly,
        fullScreenAllowed: true,
      );

      expect(details.category, isNot(AndroidNotificationCategory.call));
      expect(details.fullScreenIntent, isFalse);
    });
  });
}
