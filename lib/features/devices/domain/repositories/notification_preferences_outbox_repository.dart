import '../entities/notification_preferences_outbox_entry.dart';

/// Local outbox for at most one pending notification-preferences edit per
/// (authenticated user, device) pair.
///
/// This is a sync-intent cache, never a source of truth — the server's
/// representation always wins. Implementations must isolate entries by user
/// and device so one account's edit can never be read back for another.
abstract class NotificationPreferencesOutboxRepository {
  Future<NotificationPreferencesOutboxEntry?> read(
    String userId,
    String deviceId,
  );

  Future<void> write(
    String userId,
    String deviceId,
    NotificationPreferencesOutboxEntry entry,
  );

  Future<void> clear(String userId, String deviceId);
}
