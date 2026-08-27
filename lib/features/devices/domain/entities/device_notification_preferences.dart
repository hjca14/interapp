import 'dart:collection';

/// The four combinations supported by the notification-preferences contract.
enum AlertMode {
  none,
  ringOnly,
  notificationOnly,
  ringAndNotification;

  bool get includesRing => this == ringOnly || this == ringAndNotification;

  bool get includesNotification =>
      this == notificationOnly || this == ringAndNotification;

  static AlertMode from({required bool ring, required bool notification}) {
    return switch ((ring, notification)) {
      (true, true) => ringAndNotification,
      (true, false) => ringOnly,
      (false, true) => notificationOnly,
      (false, false) => none,
    };
  }
}

enum QuietScheduleBehavior { notificationOnly, blockAll }

/// Framework-free, validated hour/minute value.
class ClockTime {
  ClockTime({required int hour, required int minute})
    : _hour = _validHour(hour),
      _minute = _validMinute(minute);

  final int _hour;
  final int _minute;

  int get hour => _hour;
  int get minute => _minute;

  static int _validHour(int value) {
    if (value < 0 || value > 23) {
      throw ArgumentError.value(value, 'hour', 'must be between 0 and 23');
    }
    return value;
  }

  static int _validMinute(int value) {
    if (value < 0 || value > 59) {
      throw ArgumentError.value(value, 'minute', 'must be between 0 and 59');
    }
    return value;
  }

  static ClockTime? tryParse(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return ClockTime(hour: hour, minute: minute);
  }

  String get wireValue =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class QuietSchedule {
  QuietSchedule({
    this.enabled = false,
    String? timezone,
    Set<int> days = const {},
    this.startTime,
    this.endTime,
    this.behavior = QuietScheduleBehavior.notificationOnly,
  }) : timezone = _validatedTimezone(timezone),
       _days = Set<int>.unmodifiable(_validatedDays(days));

  final bool enabled;
  final String? timezone;
  final Set<int> _days;
  final ClockTime? startTime;
  final ClockTime? endTime;
  final QuietScheduleBehavior behavior;

  Set<int> get days => UnmodifiableSetView(_days);

  static String? _validatedTimezone(String? value) {
    if (value != null && value.trim().isEmpty) {
      throw ArgumentError.value(value, 'timezone', 'must not be empty');
    }
    return value;
  }

  static Set<int> _validatedDays(Set<int> values) {
    if (values.any((day) => day < 1 || day > 7)) {
      throw ArgumentError.value(values, 'days', 'must contain ISO days 1..7');
    }
    return values;
  }

  QuietSchedule copyWith({
    bool? enabled,
    Object? timezone = _unset,
    Set<int>? days,
    Object? startTime = _unset,
    Object? endTime = _unset,
    QuietScheduleBehavior? behavior,
  }) {
    return QuietSchedule(
      enabled: enabled ?? this.enabled,
      timezone: identical(timezone, _unset) ? this.timezone : timezone as String?,
      days: days ?? _days,
      startTime: identical(startTime, _unset)
          ? this.startTime
          : startTime as ClockTime?,
      endTime: identical(endTime, _unset)
          ? this.endTime
          : endTime as ClockTime?,
      behavior: behavior ?? this.behavior,
    );
  }

  String? validate() {
    if (!enabled) return null;
    if (timezone == null) {
      return 'Não foi possível obter o fuso horário do aparelho.';
    }
    if (_days.isEmpty) return 'Selecione pelo menos um dia.';
    if (startTime == null || endTime == null) return 'Informe os dois horários.';
    if (startTime == endTime) return 'Os horários devem ser diferentes.';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is QuietSchedule &&
      enabled == other.enabled &&
      timezone == other.timezone &&
      _setEquals(_days, other._days) &&
      startTime == other.startTime &&
      endTime == other.endTime &&
      behavior == other.behavior;

  @override
  int get hashCode => Object.hash(
    enabled,
    timezone,
    Object.hashAll(_days.toList()..sort()),
    startTime,
    endTime,
    behavior,
  );
}

class DeviceNotificationPreferences {
  DeviceNotificationPreferences({
    this.version = 1,
    this.alertMode = AlertMode.ringAndNotification,
    QuietSchedule? quietSchedule,
    this.updatedAt,
  }) : quietSchedule = quietSchedule ?? QuietSchedule();

  final int version;
  final AlertMode alertMode;
  final QuietSchedule quietSchedule;
  final DateTime? updatedAt;

  /// Compares only values that the user can PATCH.
  bool hasSameEditableValues(DeviceNotificationPreferences other) {
    return alertMode == other.alertMode && quietSchedule == other.quietSchedule;
  }

  DeviceNotificationPreferences copyWith({
    int? version,
    AlertMode? alertMode,
    QuietSchedule? quietSchedule,
    Object? updatedAt = _unset,
  }) {
    return DeviceNotificationPreferences(
      version: version ?? this.version,
      alertMode: alertMode ?? this.alertMode,
      quietSchedule: quietSchedule ?? this.quietSchedule,
      updatedAt: identical(updatedAt, _unset)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  DeviceNotificationPreferences withDefaultEditableValues() {
    return copyWith(
      alertMode: AlertMode.ringAndNotification,
      quietSchedule: QuietSchedule(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceNotificationPreferences &&
      version == other.version &&
      alertMode == other.alertMode &&
      quietSchedule == other.quietSchedule &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(version, alertMode, quietSchedule, updatedAt);
}

const _unset = Object();

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
