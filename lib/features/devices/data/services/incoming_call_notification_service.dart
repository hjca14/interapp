import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows a local notification when an InterBridge device reports an
/// incoming call.
///
/// This only works while the app process is alive (foreground or
/// backgrounded). Waking the app from a fully closed state requires a
/// remote push sent by a backend, which does not exist yet (Fase 4 do
/// roadmap). A future push-based implementation can reuse this service to
/// render the notification once the payload arrives.
class IncomingCallNotificationService {
  IncomingCallNotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  // High importance/priority so Android shows this as a heads-up
  // notification (pops on screen) instead of sitting silently in the tray.
  static const _androidDetails = AndroidNotificationDetails(
    'incoming_call',
    'Chamadas do interfone',
    channelDescription: 'Avisos de chamada recebida no InterBridge',
    importance: Importance.max,
    priority: Priority.high,
  );

  /// Registers the notification channel/settings and asks the OS for
  /// permission to show notifications. Must run once before [showIncomingCall]
  /// — called from `main()` before the app's first frame.
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
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
        android: _androidDetails,
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
