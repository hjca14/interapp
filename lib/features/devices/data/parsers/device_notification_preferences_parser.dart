import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';

class DeviceNotificationPreferencesParser {
  const DeviceNotificationPreferencesParser();

  DeviceNotificationPreferences parse(Map<String, dynamic> json) {
    try {
      if (json.keys.toSet().containsAll({
            'version', 'alert_mode', 'quiet_schedule', 'updated_at',
          }) ==
          false) {
        throw const FormatException('missing field');
      }
      if (json['version'] != 1) throw const FormatException('version');
      final scheduleJson = json['quiet_schedule'];
      if (scheduleJson is! Map<String, dynamic> ||
          !scheduleJson.keys.toSet().containsAll({
            'enabled', 'timezone', 'days', 'start_time', 'end_time', 'behavior',
          })) {
        throw const FormatException('schedule');
      }
      final enabled = scheduleJson['enabled'];
      final timezone = scheduleJson['timezone'];
      final rawDays = scheduleJson['days'];
      if (enabled is! bool ||
          timezone is! String? ||
          rawDays is! List ||
          rawDays.any((day) => day is! int || day < 1 || day > 7)) {
        throw const FormatException('schedule values');
      }
      final days = rawDays.cast<int>().toSet();
      if (days.length != rawDays.length) throw const FormatException('days');
      final start = _nullableTime(scheduleJson['start_time']);
      final end = _nullableTime(scheduleJson['end_time']);
      final schedule = QuietSchedule(
        enabled: enabled,
        timezone: timezone,
        days: days,
        startTime: start,
        endTime: end,
        behavior: _behavior(scheduleJson['behavior']),
      );
      if (enabled && schedule.validate() != null) {
        throw const FormatException('incomplete schedule');
      }
      final updatedAt = _updatedAt(json['updated_at']);
      return DeviceNotificationPreferences(
        alertMode: _alertMode(json['alert_mode']),
        quietSchedule: schedule,
        updatedAt: updatedAt,
      );
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'A resposta do serviço é incompatível.',
      );
    }
  }

  Map<String, dynamic> patch(
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) {
    final result = <String, dynamic>{};
    if (baseline.alertMode != draft.alertMode) {
      result['alert_mode'] = _alertWire(draft.alertMode);
    }
    final before = baseline.quietSchedule;
    final after = draft.quietSchedule;
    final quiet = <String, dynamic>{};
    if (before.enabled != after.enabled) quiet['enabled'] = after.enabled;
    if (before.timezone != after.timezone) quiet['timezone'] = after.timezone;
    if (!_sameDays(before.days, after.days)) {
      quiet['days'] = after.days.toList()..sort();
    }
    if (before.startTime != after.startTime) {
      quiet['start_time'] = after.startTime?.wireValue;
    }
    if (before.endTime != after.endTime) {
      quiet['end_time'] = after.endTime?.wireValue;
    }
    if (before.behavior != after.behavior) {
      quiet['behavior'] = _behaviorWire(after.behavior);
    }
    if (quiet.isNotEmpty) result['quiet_schedule'] = quiet;
    return result;
  }

  ClockTime? _nullableTime(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('time');
    final parsed = ClockTime.tryParse(raw);
    if (parsed == null) throw const FormatException('time');
    return parsed;
  }

  DateTime? _updatedAt(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('updated_at');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('updated_at');
    }
    return parsed;
  }

  AlertMode _alertMode(Object? raw) => switch (raw) {
    'NONE' => AlertMode.none,
    'RING_ONLY' => AlertMode.ringOnly,
    'NOTIFICATION_ONLY' => AlertMode.notificationOnly,
    'RING_AND_NOTIFICATION' => AlertMode.ringAndNotification,
    _ => throw const FormatException('alert_mode'),
  };
  QuietScheduleBehavior _behavior(Object? raw) => switch (raw) {
    'NOTIFICATION_ONLY' => QuietScheduleBehavior.notificationOnly,
    'BLOCK_ALL' => QuietScheduleBehavior.blockAll,
    _ => throw const FormatException('behavior'),
  };
  String _alertWire(AlertMode mode) => switch (mode) {
    AlertMode.none => 'NONE',
    AlertMode.ringOnly => 'RING_ONLY',
    AlertMode.notificationOnly => 'NOTIFICATION_ONLY',
    AlertMode.ringAndNotification => 'RING_AND_NOTIFICATION',
  };
  String _behaviorWire(QuietScheduleBehavior behavior) => switch (behavior) {
    QuietScheduleBehavior.notificationOnly => 'NOTIFICATION_ONLY',
    QuietScheduleBehavior.blockAll => 'BLOCK_ALL',
  };
  bool _sameDays(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}
