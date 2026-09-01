import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/push/full_screen_intent_access.dart';
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
  IncomingCallNotificationService(
    this._plugin, {
    this.onRingNotificationTap,
    FullScreenIntentChecker? fullScreenIntentChecker,
  }) : _fullScreenIntentChecker =
           fullScreenIntentChecker ?? checkFullScreenIntentAccess;

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String? payload)? onRingNotificationTap;

  // Powers only [hasFullScreenIntentAccess]/[requestFullScreenIntentAccess]
  // for `SecuritySettingsPage`'s informational status — [present] never
  // reads this. See [androidChannelFor] for why.
  final FullScreenIntentChecker _fullScreenIntentChecker;

  // High importance/priority so Android shows this as a heads-up
  // notification (pops on screen) instead of sitting silently in the tray.
  // Reused for RING_ONLY/RING_AND_NOTIFICATION, differentiated only by the
  // per-notification `category`/`fullScreenIntent` added in
  // [androidChannelFor] — both stay on this same channel id, since neither
  // property is a channel-level setting Android would otherwise freeze at
  // creation (unlike importance/sound, which is why NOTIFICATION_ONLY still
  // needs its own channel below).
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
  // Never gets a `category`/`fullScreenIntent` — see [androidChannelFor].
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
  /// assert on sound/vibration/category/full-screen without touching the
  /// plugin (channel objects are plain values — no platform channel
  /// involved).
  ///
  /// RING_ONLY/RING_AND_NOTIFICATION always request `fullScreenIntent`.
  /// This never consults [checkFullScreenIntentAccess]: that check talks to
  /// a `MainActivity`-only `MethodChannel`, which has no guarantee of being
  /// registered when a `RING_DETECTED` push arrives through the FCM
  /// background isolate with the app backgrounded or fully closed — exactly
  /// the lock-screen scenario this notification exists for. Requesting
  /// full-screen unconditionally and letting Android itself fall back to a
  /// heads-up alert when `USE_FULL_SCREEN_INTENT` access is not held (or
  /// when it otherwise decides not to launch over the lock screen) works
  /// from any process state, with or without an Activity. The MethodChannel
  /// check still exists, but only to power `SecuritySettingsPage`'s
  /// informational status — see [hasFullScreenIntentAccess]. No
  /// [AndroidNotificationAction] is ever attached: "Atender"/"Dispensar"
  /// live only in `IncomingCallPage`, reached through the same tap/
  /// full-screen `PendingIntent` and [RingCallNavigationCoordinator] as
  /// every other path — never a background-isolate action shortcut.
  @visibleForTesting
  static AndroidNotificationDetails androidChannelFor(
    RingPresentationIntent intent,
  ) {
    if (intent == RingPresentationIntent.notificationOnly) {
      return _silentChannel;
    }
    return AndroidNotificationDetails(
      _callChannel.channelId,
      _callChannel.channelName,
      channelDescription: _callChannel.channelDescription,
      importance: _callChannel.importance,
      priority: _callChannel.priority,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
    );
  }

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
  ///
  /// Deliberately synchronous in its decision-making — it never awaits
  /// [_fullScreenIntentChecker] or anything else `MainActivity`-dependent.
  /// This must work unattended from the FCM background isolate with the
  /// app backgrounded or fully closed and the device locked, where no
  /// Activity is guaranteed to exist; see [androidChannelFor].
  @override
  Future<void> present(RingDetectedEvent event) async {
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

  /// Read-only status for `SecuritySettingsPage` to render — never
  /// navigates, unlike [requestFullScreenIntentAccess]. Purely
  /// informational: [present] never calls this, and nothing about push
  /// presentation depends on its result.
  Future<bool> hasFullScreenIntentAccess() => _fullScreenIntentChecker();

  /// Voluntary, user-initiated only — never call this from `main()`, login,
  /// or push receipt. On Android <14 always resolves `true` immediately
  /// with no navigation; on 14+, resolves `true` immediately if access is
  /// already held, otherwise opens the official
  /// `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` Settings screen and
  /// resolves once the user returns. See `SecuritySettingsPage`, the only
  /// caller.
  Future<bool> requestFullScreenIntentAccess() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestFullScreenIntentPermission();
    return granted ?? false;
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
