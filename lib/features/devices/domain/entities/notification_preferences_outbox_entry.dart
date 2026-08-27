import 'device_notification_preferences.dart';

/// A minimal, locally-persisted record of a notification-preferences edit
/// that has not yet been confirmed by the server.
///
/// Exists only to survive the app being killed between initiating and
/// confirming a PATCH — it is a sync intent, never a source of truth. The
/// server's response always wins once it arrives.
class NotificationPreferencesOutboxEntry {
  const NotificationPreferencesOutboxEntry({
    required this.pendingDraft,
    required this.baselineUpdatedAt,
  });

  /// The editable values (alert mode + quiet schedule) chosen but not yet
  /// confirmed by the server.
  final DeviceNotificationPreferences pendingDraft;

  /// `updatedAt` of the baseline [pendingDraft] was computed against, used on
  /// reopen to tell whether the server has since moved on without us.
  final DateTime? baselineUpdatedAt;
}
