import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/data/repositories/local_device_connection_repository.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

final devicesRepositoryProvider = Provider<LocalDevicesRepository>(
  (_) => LocalDevicesRepository(),
);

final deviceConnectionRepositoryProvider = Provider<DeviceConnectionRepository>(
  (_) => LocalDeviceConnectionRepository(),
);

final favoritesRepositoryProvider = Provider<LocalFavoritesRepository>(
  (_) => LocalFavoritesRepository(),
);

final profileRepositoryProvider = Provider<LocalProfileRepository>(
  (_) => LocalProfileRepository(),
);

final incomingCallNotificationServiceProvider = Provider<IncomingCallNotificationService>(
  (_) => IncomingCallNotificationService(FlutterLocalNotificationsPlugin()),
);
