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
  });
}
