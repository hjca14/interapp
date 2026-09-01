import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/push/device_event_notification_intent.dart';
import '../../../../core/push/full_screen_intent_access.dart';
import '../../../../core/push/ring_detected_event.dart';
import '../../../../core/push/ring_detected_presenter.dart';
import '../../../../core/push/ring_call_intent.dart';

/// `Notification.FLAG_INSISTENT` (Android public API, stable since API 1):
/// repeats the notification's sound/vibration continuously until it is
/// canceled, instead of alerting once. This is the pre-`ConnectionService`
/// mechanism Android itself historically used for the ringing phone call
/// experience, and remains valid/documented for apps that do not use
/// `ConnectionService`/`InCallService` (explicitly out of scope for this
/// PR — see `docs/PHASE_3_ROADMAP.md`). Not exposed as a named constant by
/// `flutter_local_notifications` — passed through its own
/// `additionalFlags` escape hatch, which the plugin ORs directly onto the
/// built `android.app.Notification.flags`.
const _flagInsistent = 0x00000004;

/// Shows local notifications for InterBridge calling activity: the
/// device-status-polling "incoming call" experience below, and — via
/// [present]/[endCall] — a validated `RING_DETECTED`/`RING_ENDED` push.
///
/// The polling-based [showIncomingCall] only works while the app process is
/// alive (foreground or backgrounded); [present] additionally works from a
/// fully closed app through the FCM background isolate handler, since it is
/// also instantiated there — see `firebaseMessagingBackgroundHandler`.
class IncomingCallNotificationService implements RingNotificationPresenter {
  IncomingCallNotificationService(
    this._plugin, {
    this.onRingNotificationTap,
    this.onCallEnded,
    this.onCallPresented,
    FullScreenIntentChecker? fullScreenIntentChecker,
  }) : _fullScreenIntentChecker =
           fullScreenIntentChecker ?? checkFullScreenIntentAccess;

  final FlutterLocalNotificationsPlugin _plugin;

  /// [notificationId] is the OS's own id for the tapped notification —
  /// always the exact same id [present]/[showIncomingCall] used, whatever
  /// its `payload` turns out to say (or fails to say). Callers needing to
  /// safely recover from an invalid/expired call tap (see
  /// `routeNotificationTap`) must cancel by this id, never by recomputing
  /// one from the payload — an invalid payload cannot be trusted to derive
  /// anything from, including which notification it was.
  final void Function(String? payload, int? notificationId)?
  onRingNotificationTap;

  /// Notified with `callId` whenever [endCall] cancels a call's
  /// notification — production wiring forwards this to
  /// `RingCallNavigationCoordinator.endCall` so a `RING_ENDED`/local timeout
  /// closes an already-open `IncomingCallPage`/pending open too, not just
  /// the notification. Left `null` in the background isolate, which has no
  /// navigation to affect.
  final void Function(String callId)? onCallEnded;

  /// Notified with [event] whenever [present] shows a call-mode
  /// notification (`RING_ONLY`/legacy `RING_AND_NOTIFICATION`) —
  /// `NOTIFICATION_ONLY` never calls this. Production wiring on the
  /// instance the *foreground* listener presents through forwards this
  /// straight to `RingCallNavigationCoordinator.acceptSerialized`, so a call
  /// arriving while InterBridge itself is already in foreground opens
  /// `IncomingCallPage` immediately — without depending on Android's
  /// full-screen-intent decision, which the OS may legitimately skip while
  /// the app (or another app) is already frontmost. Left `null` on the
  /// background-isolate instance: a push arriving through
  /// `firebaseMessagingBackgroundHandler` has no foreground UI to jump into,
  /// and must rely on the notification tap/full-screen-intent path instead.
  final void Function(RingDetectedEvent event)? onCallPresented;

  // Powers only [hasFullScreenIntentAccess]/[requestFullScreenIntentAccess]
  // for `SecuritySettingsPage`'s informational status — [present] never
  // reads this. See [androidChannelFor] for why.
  final FullScreenIntentChecker _fullScreenIntentChecker;

  // Versioned (`_v2`, bumped from the pre-existing `incoming_call`
  // alongside this same change): Android freezes a channel's
  // sound/vibration/importance the first time it is created, and this
  // revision changes all three (continuous ringtone, `FLAG_INSISTENT`,
  // ringtone audio usage) — reusing the old id would silently keep
  // whatever settings an already-installed app's channel already has.
  // ANY future semantic change here (sound, vibration, importance, audio
  // usage) requires bumping this id again, not editing these fields in
  // place.
  static const _callChannel = AndroidNotificationDetails(
    'incoming_call_v2',
    'Chamadas do interfone',
    channelDescription: 'Avisos de chamada recebida no InterBridge',
    importance: Importance.max,
    priority: Priority.high,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  // Versioned (`_v1`): a genuinely new channel, replacing the previous
  // `ring_notification_silent` (which forced `playSound`/`enableVibration`
  // off). This one is a normal, audible "message-like" notification —
  // sound/vibration follow the channel/system defaults, which the user can
  // still further customize from Android's own channel settings once
  // created; the app never re-silences it in code. See the versioning note
  // on [_callChannel] — bump this id, never edit it in place, for any
  // future change to sound/vibration/importance here.
  static const _deviceNotificationChannel = AndroidNotificationDetails(
    'device_notification_v1',
    'Notificações do interfone',
    channelDescription: 'Avisos de eventos do interfone',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _ringDetectedNotificationTitle = 'Interfone tocando';
  static const _ringDetectedNotificationBody = 'Alguém chamou no interfone.';

  /// Exposes the channel [present] would use for [intent], so tests can
  /// assert on sound/vibration/category/full-screen without touching the
  /// plugin (channel objects are plain values — no platform channel
  /// involved).
  ///
  /// RING_ONLY/RING_AND_NOTIFICATION (call mode — see
  /// [RingPresentationIntentCall.isCall]) always request `fullScreenIntent`
  /// and set up a continuous, insistent ringtone (`FLAG_INSISTENT`,
  /// `USE_FULL_SCREEN_INTENT`+`notificationRingtone` audio usage, `ongoing`
  /// so a stray swipe cannot dismiss it, and a 60s `timeoutAfter` — the same
  /// local ring-timeout duration `RingCallNavigationCoordinator` applies to
  /// the UI/navigation side, enforced by Android itself so it holds even if
  /// the app process is not alive to run a Dart timer). This never consults
  /// [checkFullScreenIntentAccess]: that check talks to a `MainActivity`-
  /// only `MethodChannel`, which has no guarantee of being registered when a
  /// `RING_DETECTED` push arrives through the FCM background isolate with
  /// the app backgrounded or fully closed — exactly the lock-screen scenario
  /// this notification exists for. Requesting full-screen unconditionally
  /// and letting Android itself fall back to a heads-up alert when
  /// `USE_FULL_SCREEN_INTENT` access is not held (or when it otherwise
  /// decides not to launch over the lock screen) works from any process
  /// state, with or without an Activity. The MethodChannel check still
  /// exists, but only to power `SecuritySettingsPage`'s informational status
  /// — see [hasFullScreenIntentAccess].
  ///
  /// `NOTIFICATION_ONLY` gets a plain, audible notification on
  /// [_deviceNotificationChannel]: no call category, no full-screen intent,
  /// not ongoing, no insistent flag.
  ///
  /// No [AndroidNotificationAction] is ever attached to either: "Atender"/
  /// "Dispensar" live only in `IncomingCallPage`, reached through the same
  /// tap/full-screen `PendingIntent` and [RingCallNavigationCoordinator] as
  /// every other path — never a background-isolate action shortcut.
  @visibleForTesting
  static AndroidNotificationDetails androidChannelFor(
    RingPresentationIntent intent,
  ) {
    if (!intent.isCall) {
      return _deviceNotificationChannel;
    }
    return AndroidNotificationDetails(
      _callChannel.channelId,
      _callChannel.channelName,
      channelDescription: _callChannel.channelDescription,
      importance: _callChannel.importance,
      priority: _callChannel.priority,
      audioAttributesUsage: _callChannel.audioAttributesUsage,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      timeoutAfter: _ringTimeoutMs,
      additionalFlags: Int32List.fromList(<int>[_flagInsistent]),
    );
  }

  /// Mirrors `RingCallNavigationCoordinator`'s default ring timeout (60s) —
  /// see [androidChannelFor]'s doc for why both need the same value.
  static const _ringTimeoutMs = 60000;

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
        onRingNotificationTap?.call(response.payload, response.id);
      },
    );
  }

  /// Consumes a local-notification cold start after plugin setup. Kept
  /// separate from the callback because Android reports this path through
  /// launch details rather than [onDidReceiveNotificationResponse].
  Future<void> consumeInitialNotificationLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      onRingNotificationTap?.call(
        details?.notificationResponse?.payload,
        details?.notificationResponse?.id,
      );
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
  ///
  /// Call-mode notifications are id'd from [RingPushEvent.callId] (not
  /// `eventId`): a repeated `RING_DETECTED` for the same call replaces
  /// rather than stacks, and [endCall]/the local ring-timeout can cancel it
  /// by `call_id` alone. `NOTIFICATION_ONLY` is id'd from `eventId` instead
  /// — each is its own event, not part of a call to later replace/cancel by
  /// `call_id` — and its tap payload is a [DeviceEventNotificationIntent],
  /// not a [RingCallIntent]: it must open a device destination, never
  /// `IncomingCallPage`.
  @override
  Future<void> present(RingDetectedEvent event) async {
    if (!event.presentationIntent.isCall) {
      return _plugin.show(
        id: ringNotificationId('notification:${event.eventId}'),
        title: _ringDetectedNotificationTitle,
        body: _ringDetectedNotificationBody,
        payload: DeviceEventNotificationIntent(
          deviceId: event.deviceId,
        ).serialize(),
        notificationDetails: NotificationDetails(
          android: androidChannelFor(event.presentationIntent),
          iOS: const DarwinNotificationDetails(presentSound: true),
        ),
      );
    }
    await _plugin.show(
      id: ringNotificationId(event.callId),
      title: _ringDetectedNotificationTitle,
      body: _ringDetectedNotificationBody,
      payload: RingCallIntent.fromEvent(event).serialize(),
      notificationDetails: NotificationDetails(
        android: androidChannelFor(event.presentationIntent),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
    );
    onCallPresented?.call(event);
  }

  /// Ends a call locally: cancels its notification (which also stops the
  /// insistent ringtone — Android's `FLAG_INSISTENT` sound/vibration always
  /// stops when the notification is canceled) and notifies [onCallEnded] so
  /// navigation can close an already-open `IncomingCallPage`/abort a
  /// pending one. A `RING_ENDED` for a call that never got this far (never
  /// presented here, already ended, or `NOTIFICATION_ONLY` — which is never
  /// id'd by `call_id`) safely cancels nothing and still reports
  /// [onCallEnded]; the coordinator's own [RingEndedEvent.callId] match
  /// makes that a no-op on its side too.
  @override
  Future<void> endCall(RingEndedEvent event) async {
    await _plugin.cancel(id: ringNotificationId(event.callId));
    onCallEnded?.call(event.callId);
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

  /// Cancels the call notification for [callId] — used when the user
  /// answers/dismisses from `IncomingCallPage`, or by the local ring-timeout
  /// via [endCall]. Stops the insistent ringtone the same way [endCall]
  /// does (canceling always does, regardless of caller).
  Future<void> cancelRing(String callId) {
    return _plugin.cancel(id: ringNotificationId(callId));
  }

  /// Cancels a notification by its exact OS-assigned [id] — used only for
  /// the safe-recovery path when a tapped call notification's payload fails
  /// to restore (see `routeNotificationTap`'s `onInvalidCallTap`), where no
  /// valid `call_id` is available to recompute [ringNotificationId] from.
  /// Never derives an id from untrusted/invalid payload content.
  Future<void> cancelNotificationById(int id) {
    return _plugin.cancel(id: id);
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
