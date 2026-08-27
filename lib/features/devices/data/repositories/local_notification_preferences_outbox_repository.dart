import 'dart:convert';

import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/entities/notification_preferences_outbox_entry.dart';
import 'package:interapp/features/devices/domain/repositories/notification_preferences_outbox_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed outbox, one entry per `userId_deviceId` key.
///
/// The stored shape is deliberately local-only (enum `.name`s, not the wire
/// contract codes) so it never has to track the network contract. Never
/// stores a token, e-mail, password, or raw server response — only the
/// editable fields the user chose and the baseline timestamp needed to
/// reconcile safely on reopen. Any unrecognized or unversioned content is
/// discarded rather than applied.
class LocalNotificationPreferencesOutboxRepository
    implements NotificationPreferencesOutboxRepository {
  static const _formatVersion = 1;
  static const _keyPrefix = 'notification_preferences_outbox_';

  String _key(String userId, String deviceId) =>
      '$_keyPrefix${userId}_$deviceId';

  @override
  Future<NotificationPreferencesOutboxEntry?> read(
    String userId,
    String deviceId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId, deviceId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['formatVersion'] != _formatVersion) return null;

      final alertModeName = decoded['alertMode'];
      final scheduleMap = decoded['quietSchedule'];
      if (alertModeName is! String || scheduleMap is! Map<String, dynamic>) {
        return null;
      }
      final alertMode = AlertMode.values.asNameMap()[alertModeName];
      if (alertMode == null) return null;

      final schedule = _decodeSchedule(scheduleMap);
      if (schedule == null) return null;

      final baselineUpdatedAtRaw = decoded['baselineUpdatedAt'];
      DateTime? baselineUpdatedAt;
      if (baselineUpdatedAtRaw != null) {
        if (baselineUpdatedAtRaw is! String) return null;
        baselineUpdatedAt = DateTime.tryParse(baselineUpdatedAtRaw);
        if (baselineUpdatedAt == null) return null;
      }

      return NotificationPreferencesOutboxEntry(
        pendingDraft: DeviceNotificationPreferences(
          alertMode: alertMode,
          quietSchedule: schedule,
        ),
        baselineUpdatedAt: baselineUpdatedAt,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(
    String userId,
    String deviceId,
    NotificationPreferencesOutboxEntry entry,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final schedule = entry.pendingDraft.quietSchedule;
    await preferences.setString(
      _key(userId, deviceId),
      jsonEncode({
        'formatVersion': _formatVersion,
        'alertMode': entry.pendingDraft.alertMode.name,
        'quietSchedule': {
          'enabled': schedule.enabled,
          'timezone': schedule.timezone,
          'days': schedule.days.toList()..sort(),
          'startTime': schedule.startTime?.wireValue,
          'endTime': schedule.endTime?.wireValue,
          'behavior': schedule.behavior.name,
        },
        'baselineUpdatedAt': entry.baselineUpdatedAt?.toIso8601String(),
      }),
    );
  }

  @override
  Future<void> clear(String userId, String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(userId, deviceId));
  }

  QuietSchedule? _decodeSchedule(Map<String, dynamic> map) {
    final enabled = map['enabled'];
    final timezone = map['timezone'];
    final rawDays = map['days'];
    final startTimeRaw = map['startTime'];
    final endTimeRaw = map['endTime'];
    final behaviorName = map['behavior'];

    if (enabled is! bool) return null;
    if (timezone != null && timezone is! String) return null;
    if (rawDays is! List) return null;
    if (rawDays.any((day) => day is! int)) return null;
    final days = rawDays.cast<int>().toSet();
    if (days.any((day) => day < 1 || day > 7)) return null;

    if (startTimeRaw != null && startTimeRaw is! String) return null;
    if (endTimeRaw != null && endTimeRaw is! String) return null;
    final startTime = startTimeRaw == null
        ? null
        : ClockTime.tryParse(startTimeRaw as String);
    if (startTimeRaw != null && startTime == null) return null;
    final endTime = endTimeRaw == null
        ? null
        : ClockTime.tryParse(endTimeRaw as String);
    if (endTimeRaw != null && endTime == null) return null;

    if (behaviorName is! String) return null;
    final behavior = QuietScheduleBehavior.values.asNameMap()[behaviorName];
    if (behavior == null) return null;

    try {
      return QuietSchedule(
        enabled: enabled,
        timezone: timezone as String?,
        days: days,
        startTime: startTime,
        endTime: endTime,
        behavior: behavior,
      );
    } on ArgumentError {
      return null;
    }
  }
}
