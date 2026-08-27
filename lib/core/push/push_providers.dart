import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_messaging_client.dart';
import 'push_notification_service.dart';

/// Built once per process. `main()` still has to call `.initialize()` on it
/// before its token/permission state is populated.
final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (_) => PushNotificationService(FirebaseMessagingClient()),
);
