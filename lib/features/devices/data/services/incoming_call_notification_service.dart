import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/push/ring_detected_event.dart';
import '../../../../core/push/ring_detected_presenter.dart';
import '../../../../core/push/ring_call_intent.dart';

/// Shows local notifications for InterBridge calling activity: the
/// device-status-polling "incoming call" experience below, and — via
/// [present] — a validated `RING_DETECTED` push (Fase 3B.9's minimal
/// slice).
///
/// The polling-based [showIncomingCall] only works while the app process is
/// alive (foreground or backgrounded); [present] additionally works from a
/// fully closed app through the FCM background isolate handler, since it is
/// also instantiated there — see `firebaseMessagingBackgroundHandler`.
class IncomingCallNotificationService implements RingNotificationPresenter {
  IncomingCallNotificationService(this._plugin, {this.onRingNotificationTap});

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String? payload)? onRingNotificationTap;

  // High importance/priority so Android shows this as a heads-up
  // notification (pops on screen) instead of sitting silently in the tray.
  // Reused for RING_ONLY/RING_AND_NOTIFICATION: at this stage both are
  // presented identically (a ringing-style local notification with sound);
  // differentiating them further belongs to the real call experience in
  // Fase 3B.9.
  static const _callChannel = AndroidNotificationDetails(
    'incoming_call',
    'Chamadas do interfone',
    channelDescription: 'Avisos de chamada recebida no InterBridge',
    importance: Importance.max,
    priority: Priority.high,
  );

  // Separate channel for NOTIFICATION_ONLY: Android bakes sound/vibration
  // into the channel itself once created, so a silent presentation needs
  // its own channel rather than per-call flags on the shared one above.
  static const _silentChannel = AndroidNotificationDetails(
    'ring_notification_silent',
    'Notificações silenciosas do interfone',
    channelDescription: 'Avisos do interfone sem som nem vibração de chamada',
    importance: Importance.high,
    priority: Priority.high,
    playSound: false,
    enableVibration: false,
  );

  static const _ringDetectedNotificationTitle = 'Interfone tocando';
  static const _ringDetectedNotificationBody = 'Alguém chamou no interfone.';

  /// Exposes the channel [present] would use for [intent], so tests can
  /// assert on sound/vibration without touching the plugin (channel
  /// objects are plain values — no platform channel involved).
  @visibleForTesting
  static AndroidNotificationDetails androidChannelFor(
    RingPresentationIntent intent,
  ) => intent == RingPresentationIntent.notificationOnly
      ? _silentChannel
      : _callChannel;

  /// Registers the notification channel/settings and asks the OS for
  /// permission to show notifications. Must run once before
  /// [showIncomingCall]/[present] — called from `main()` before the app's
  /// first frame.
  Future<void> initialize() async {
    await _initializePlatformSettings();
    await _requestPermissions();
  }

  /// Channel/plugin setup only, without requesting permission — safe to
  /// call from the FCM background isolate, which has no UI to show a
  /// system permission prompt over and should not need to (permission is
  /// already requested from the main isolate's [initialize]).
  Future<void> initializeForBackgroundIsolate() =>
      _initializePlatformSettings();

  Future<void> _initializePlatformSettings() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        onRingNotificationTap?.call(response.payload);
      },
    );
  }

  /// Consumes a local-notification cold start after plugin setup. Kept
  /// separate from the callback because Android reports this path through
  /// launch details rather than [onDidReceiveNotificationResponse].
  Future<void> consumeInitialNotificationLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      onRingNotificationTap?.call(details?.notificationResponse?.payload);
    }
  }

  Future<void> _requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
  }

  /// Presents a validated `RING_DETECTED` event per its
  /// `presentation_intent`. Generic text on purpose — the push contract
  /// does not yet carry a trustworthy device display name, and [event]'s
  /// `deviceId` must never be shown as one.
  @override
  Future<void> present(RingDetectedEvent event) {
    final silent =
        event.presentationIntent == RingPresentationIntent.notificationOnly;
    return _plugin.show(
      id: ringNotificationId(event.eventId),
      title: _ringDetectedNotificationTitle,
      body: _ringDetectedNotificationBody,
      payload: RingCallIntent.fromEvent(event).serialize(),
      notificationDetails: NotificationDetails(
        android: androidChannelFor(event.presentationIntent),
        iOS: DarwinNotificationDetails(presentSound: !silent),
      ),
    );
  }

  Future<void> cancelRing(String eventId) {
    return _plugin.cancel(id: ringNotificationId(eventId));
  }

  /// Shows the "device X is calling" notification. [deviceId]'s hash code is
  /// used as the notification id so a second call for the same device
  /// replaces (rather than stacks) the first, and [cancelIncomingCall] can
  /// target the right one.
  Future<void> showIncomingCall(String deviceId, String deviceName) {
    return _plugin.show(
      id: deviceId.hashCode,
      title: 'Chamada recebida',
      body: '$deviceName está chamando pelo interfone.',
      notificationDetails: const NotificationDetails(
        android: _callChannel,
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  /// Dismisses the notification shown by [showIncomingCall] for [deviceId],
  /// e.g. once the call ends or the user answers/declines in-app.
  Future<void> cancelIncomingCall(String deviceId) {
    return _plugin.cancel(id: deviceId.hashCode);
  }
}
