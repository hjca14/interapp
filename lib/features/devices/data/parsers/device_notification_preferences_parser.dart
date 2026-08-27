import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';

class DeviceNotificationPreferencesParser {
  const DeviceNotificationPreferencesParser();

  static const _topLevelKeys = {
    'version',
    'alert_mode',
    'quiet_schedule',
    'updated_at',
  };
  static const _scheduleKeys = {
    'enabled',
    'timezone',
    'days',
    'start_time',
    'end_time',
    'behavior',
  };

  DeviceNotificationPreferences parse(Map<String, dynamic> json) {
    try {
      _requireExactKeys(json, _topLevelKeys);
      if (json['version'] != 1) throw const FormatException();

      final rawSchedule = json['quiet_schedule'];
      if (rawSchedule is! Map<String, dynamic>) throw const FormatException();
      _requireExactKeys(rawSchedule, _scheduleKeys);

      final enabled = rawSchedule['enabled'];
      final timezone = rawSchedule['timezone'];
      final rawDays = rawSchedule['days'];
      if (enabled is! bool ||
          (timezone != null && timezone is! String) ||
          timezone == '' ||
          rawDays is! List<dynamic> ||
          rawDays.any((day) => day is! int || day < 1 || day > 7)) {
        throw const FormatException();
      }

      final days = rawDays.cast<int>().toSet();
      if (days.length != rawDays.length) throw const FormatException();

      final schedule = QuietSchedule(
        enabled: enabled,
        timezone: timezone as String?,
        days: days,
        startTime: _nullableTime(rawSchedule['start_time']),
        endTime: _nullableTime(rawSchedule['end_time']),
        behavior: _behavior(rawSchedule['behavior']),
      );
      if (enabled && schedule.validate() != null) throw const FormatException();

      return DeviceNotificationPreferences(
        version: 1,
        alertMode: _alertMode(json['alert_mode']),
        quietSchedule: schedule,
        updatedAt: _updatedAt(json['updated_at']),
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
    if (before.timezone != after.timezone) {
      quiet['timezone'] = after.timezone;
    }
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

  void _requireExactKeys(Map<String, dynamic> value, Set<String> expected) {
    final keys = value.keys.toSet();
    if (keys.length != expected.length || !keys.containsAll(expected)) {
      throw const FormatException();
    }
  }

  ClockTime? _nullableTime(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException();
    final parsed = ClockTime.tryParse(raw);
    if (parsed == null) throw const FormatException();
    return parsed;
  }

  DateTime? _updatedAt(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException();
    final parsed = DateTime.tryParse(raw);
    final hasUtcSuffix =
        raw.endsWith('Z') || RegExp(r'[+-]00:00$').hasMatch(raw);
    if (parsed == null || !parsed.isUtc || !hasUtcSuffix) {
      throw const FormatException();
    }
    return parsed;
  }

  AlertMode _alertMode(Object? raw) => switch (raw) {
    'NONE' => AlertMode.none,
    'RING_ONLY' => AlertMode.ringOnly,
    'NOTIFICATION_ONLY' => AlertMode.notificationOnly,
    'RING_AND_NOTIFICATION' => AlertMode.ringAndNotification,
    _ => throw const FormatException(),
  };

  QuietScheduleBehavior _behavior(Object? raw) => switch (raw) {
    'NOTIFICATION_ONLY' => QuietScheduleBehavior.notificationOnly,
    'BLOCK_ALL' => QuietScheduleBehavior.blockAll,
    _ => throw const FormatException(),
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
