enum AlertMode {
  none,
  ringOnly,
  notificationOnly,
  ringAndNotification;

  bool get includesRing => this == ringOnly || this == ringAndNotification;
  bool get includesNotification =>
      this == notificationOnly || this == ringAndNotification;

  static AlertMode from({required bool ring, required bool notification}) =>
      switch ((ring, notification)) {
        (true, true) => ringAndNotification,
        (true, false) => ringOnly,
        (false, true) => notificationOnly,
        _ => none,
      };
}

enum QuietScheduleBehavior { notificationOnly, blockAll }

class ClockTime {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);
  final int hour;
  final int minute;

  static ClockTime? tryParse(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return ClockTime(hour, minute);
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
  const QuietSchedule({
    this.enabled = false,
    this.timezone,
    this.days = const {},
    this.startTime,
    this.endTime,
    this.behavior = QuietScheduleBehavior.notificationOnly,
  });
  final bool enabled;
  final String? timezone;
  final Set<int> days;
  final ClockTime? startTime;
  final ClockTime? endTime;
  final QuietScheduleBehavior behavior;

  QuietSchedule copyWith({
    bool? enabled,
    Object? timezone = _unset,
    Set<int>? days,
    Object? startTime = _unset,
    Object? endTime = _unset,
    QuietScheduleBehavior? behavior,
  }) => QuietSchedule(
    enabled: enabled ?? this.enabled,
    timezone: identical(timezone, _unset) ? this.timezone : timezone as String?,
    days: days ?? this.days,
    startTime: identical(startTime, _unset)
        ? this.startTime
        : startTime as ClockTime?,
    endTime: identical(endTime, _unset) ? this.endTime : endTime as ClockTime?,
    behavior: behavior ?? this.behavior,
  );

  String? validate() {
    if (!enabled) return null;
    if (timezone == null || timezone!.trim().isEmpty) {
      return 'Não foi possível obter o fuso horário do aparelho.';
    }
    if (days.isEmpty) return 'Selecione pelo menos um dia.';
    if (startTime == null || endTime == null) return 'Informe os dois horários.';
    if (startTime == endTime) return 'Os horários devem ser diferentes.';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is QuietSchedule &&
      enabled == other.enabled &&
      timezone == other.timezone &&
      _setEquals(days, other.days) &&
      startTime == other.startTime &&
      endTime == other.endTime &&
      behavior == other.behavior;
  @override
  int get hashCode => Object.hash(
    enabled,
    timezone,
    Object.hashAll(days.toList()..sort()),
    startTime,
    endTime,
    behavior,
  );
}

class DeviceNotificationPreferences {
  const DeviceNotificationPreferences({
    this.version = 1,
    this.alertMode = AlertMode.ringAndNotification,
    this.quietSchedule = const QuietSchedule(),
    this.updatedAt,
  });
  final int version;
  final AlertMode alertMode;
  final QuietSchedule quietSchedule;
  final DateTime? updatedAt;

  DeviceNotificationPreferences copyWith({
    AlertMode? alertMode,
    QuietSchedule? quietSchedule,
  }) => DeviceNotificationPreferences(
    version: version,
    alertMode: alertMode ?? this.alertMode,
    quietSchedule: quietSchedule ?? this.quietSchedule,
    updatedAt: updatedAt,
  );

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
