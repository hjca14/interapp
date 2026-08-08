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

  static const _androidDetails = AndroidNotificationDetails(
    'incoming_call',
    'Chamadas do interfone',
    channelDescription: 'Avisos de chamada recebida no InterBridge',
    importance: Importance.max,
    priority: Priority.high,
  );

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

  Future<void> cancelIncomingCall(String deviceId) {
    return _plugin.cancel(id: deviceId.hashCode);
  }
}
