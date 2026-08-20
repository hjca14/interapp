/// Which network zone the phone is currently in relative to the InterBridge.
///
/// Deliberately not "wifi on/off" — being connected to *some* Wi-Fi doesn't
/// mean being on the *device's* network. Whatever eventually decides this
/// (SSID match, local discovery, etc.) is a Fase 2 concern; this only models
/// the two outcomes the rest of the app needs to react to.
enum NetworkPresence { localNetwork, remoteNetwork }

/// What happens when the interfone rings, for a given [NetworkPresence].
///
/// A single enum instead of two independent "receber ligação"/"receber
/// notificação" booleans, since only these four combinations are meaningful
/// and an enum can't represent the other 0 (there are none missing, but it
/// also can't drift into a nonsensical state the way two loose bools could).
enum CallAlertMode {
  none,
  ringOnly,
  notificationOnly,
  ringAndNotification;

  bool get includesRing => this == ringOnly || this == ringAndNotification;

  bool get includesNotification =>
      this == notificationOnly || this == ringAndNotification;

  static CallAlertMode from({required bool ring, required bool notification}) {
    if (ring && notification) {
      return ringAndNotification;
    }
    if (ring) {
      return ringOnly;
    }
    if (notification) {
      return notificationOnly;
    }
    return none;
  }
}

/// How the device should alert the user when it rings, per [NetworkPresence].
///
/// This is what both the "Chamadas" and "Presença" sections of
/// `DeviceSettingsPage` edit: the local-network mode is the default/home
/// behavior, the remote-network mode is what used to be a single "receber
/// chamadas fora da rede" toggle — modeled here as a full [CallAlertMode]
/// instead, since `remoteNetworkAlertMode == none` already expresses "don't
/// receive calls away from home" without a redundant extra flag.
class DeviceCallSettings {
  const DeviceCallSettings({
    this.localNetworkAlertMode = CallAlertMode.ringAndNotification,
    this.remoteNetworkAlertMode = CallAlertMode.notificationOnly,
  });

  final CallAlertMode localNetworkAlertMode;
  final CallAlertMode remoteNetworkAlertMode;

  CallAlertMode alertModeFor(NetworkPresence presence) {
    return presence == NetworkPresence.localNetwork
        ? localNetworkAlertMode
        : remoteNetworkAlertMode;
  }

  DeviceCallSettings copyWith({
    CallAlertMode? localNetworkAlertMode,
    CallAlertMode? remoteNetworkAlertMode,
  }) {
    return DeviceCallSettings(
      localNetworkAlertMode:
          localNetworkAlertMode ?? this.localNetworkAlertMode,
      remoteNetworkAlertMode:
          remoteNetworkAlertMode ?? this.remoteNetworkAlertMode,
    );
  }

  Map<String, dynamic> toMap() => {
    'localNetworkAlertMode': localNetworkAlertMode.name,
    'remoteNetworkAlertMode': remoteNetworkAlertMode.name,
  };

  factory DeviceCallSettings.fromMap(Map<String, dynamic> map) {
    return DeviceCallSettings(
      localNetworkAlertMode:
          _callAlertModeFromName(map['localNetworkAlertMode']) ??
          CallAlertMode.ringAndNotification,
      remoteNetworkAlertMode:
          _callAlertModeFromName(map['remoteNetworkAlertMode']) ??
          CallAlertMode.notificationOnly,
    );
  }
}

CallAlertMode? _callAlertModeFromName(Object? name) {
  if (name is! String) {
    return null;
  }
  for (final mode in CallAlertMode.values) {
    if (mode.name == name) {
      return mode;
    }
  }
  return null;
}

/// What happens to calls/notifications while quiet hours are active.
enum QuietHoursBehavior {
  /// Neither the ringing UI nor a notification is shown at all.
  blockAll,

  /// The notification still appears, just without sound/vibration.
  silentNotificationOnly,
}

QuietHoursBehavior? _quietHoursBehaviorFromName(Object? name) {
  if (name is! String) {
    return null;
  }
  for (final behavior in QuietHoursBehavior.values) {
    if (behavior.name == name) {
      return behavior;
    }
  }
  return null;
}

/// A plain hour/minute pair, independent of Flutter's `TimeOfDay` so this
/// stays a framework-free domain entity like the rest of `devices/domain`.
/// The presentation layer converts to/from `TimeOfDay` when showing a time
/// picker.
class ClockTime {
  const ClockTime({required this.hour, required this.minute});

  final int hour;
  final int minute;

  Map<String, dynamic> toMap() => {'hour': hour, 'minute': minute};

  factory ClockTime.fromMap(Map<String, dynamic> map) {
    return ClockTime(
      hour: (map['hour'] as num?)?.toInt() ?? 0,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Do-not-disturb window for one device.
///
/// [weekdays] uses 1 = Monday ... 7 = Sunday, matching `DateTime.monday`..
/// `DateTime.sunday`, instead of inventing a parallel day-of-week enum.
class QuietHoursSettings {
  const QuietHoursSettings({
    this.enabled = false,
    this.start = const ClockTime(hour: 22, minute: 0),
    this.end = const ClockTime(hour: 7, minute: 0),
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.behavior = QuietHoursBehavior.blockAll,
  });

  final bool enabled;
  final ClockTime start;
  final ClockTime end;
  final Set<int> weekdays;
  final QuietHoursBehavior behavior;

  QuietHoursSettings copyWith({
    bool? enabled,
    ClockTime? start,
    ClockTime? end,
    Set<int>? weekdays,
    QuietHoursBehavior? behavior,
  }) {
    return QuietHoursSettings(
      enabled: enabled ?? this.enabled,
      start: start ?? this.start,
      end: end ?? this.end,
      weekdays: weekdays ?? this.weekdays,
      behavior: behavior ?? this.behavior,
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'start': start.toMap(),
    'end': end.toMap(),
    'weekdays': weekdays.toList(),
    'behavior': behavior.name,
  };

  factory QuietHoursSettings.fromMap(Map<String, dynamic> map) {
    final rawWeekdays = map['weekdays'];
    return QuietHoursSettings(
      enabled: map['enabled'] as bool? ?? false,
      start: map['start'] is Map<String, dynamic>
          ? ClockTime.fromMap(map['start'] as Map<String, dynamic>)
          : const ClockTime(hour: 22, minute: 0),
      end: map['end'] is Map<String, dynamic>
          ? ClockTime.fromMap(map['end'] as Map<String, dynamic>)
          : const ClockTime(hour: 7, minute: 0),
      weekdays: rawWeekdays is List
          ? rawWeekdays.whereType<num>().map((day) => day.toInt()).toSet()
          : const {1, 2, 3, 4, 5, 6, 7},
      behavior:
          _quietHoursBehaviorFromName(map['behavior']) ??
          QuietHoursBehavior.blockAll,
    );
  }
}

/// A device's own behavior preferences — separate from [InterBridgeDevice]
/// (identity) and `DeviceStatus` (live telemetry). Persisted per `deviceId`
/// by `LocalDeviceSettingsRepository`.
///
/// These are **app/user preferences** the phone itself acts on (ring vs.
/// notification, quiet hours, door confirmation...) — not hardware
/// configuration. Values the device firmware would actually apply (e.g.
/// `door_open_duration_ms`, `health_interval_s`) belong to
/// `DeviceHardwareConfig` instead, which mirrors the device's Device Shadow
/// `desired` state. The two must never be merged into one bag: a setting
/// here can be changed instantly and only affects this app/user, while a
/// `DeviceHardwareConfig` change would need to reach the physical device.
///
/// These are settings for the *device*, shared by everyone who can access
/// it. A future `UserDeviceSettings` (per user, per device) would sit next
/// to this for preferences that shouldn't be shared — e.g. one person
/// muting their own phone without silencing it for everyone else. Not
/// needed until sharing (Fase 4) actually ships; don't build it early.
class DeviceSettings {
  const DeviceSettings({
    this.calls = const DeviceCallSettings(),
    this.quietHours = const QuietHoursSettings(),
    this.confirmBeforeOpeningDoor = true,
    this.requireDeviceAuthenticationToOpenDoor = false,
  });

  final DeviceCallSettings calls;
  final QuietHoursSettings quietHours;

  /// Whether the app should ask "tem certeza?" before sending the open-door
  /// command.
  final bool confirmBeforeOpeningDoor;

  /// Whether opening the door requires the phone's own lock screen/biometric
  /// check first. The actual biometric prompt isn't implemented yet — this
  /// only reserves the setting so the door-open flow has something to check
  /// once it is.
  final bool requireDeviceAuthenticationToOpenDoor;

  DeviceSettings copyWith({
    DeviceCallSettings? calls,
    QuietHoursSettings? quietHours,
    bool? confirmBeforeOpeningDoor,
    bool? requireDeviceAuthenticationToOpenDoor,
  }) {
    return DeviceSettings(
      calls: calls ?? this.calls,
      quietHours: quietHours ?? this.quietHours,
      confirmBeforeOpeningDoor:
          confirmBeforeOpeningDoor ?? this.confirmBeforeOpeningDoor,
      requireDeviceAuthenticationToOpenDoor:
          requireDeviceAuthenticationToOpenDoor ??
          this.requireDeviceAuthenticationToOpenDoor,
    );
  }

  /// Serializes to a JSON-ready map. Unlike the flat tab-separated entities
  /// elsewhere in `devices/domain` (`InterBridgeDevice`, `Favorite`), this
  /// one is nested and has enums/sets — `shared_preferences` storage uses
  /// `jsonEncode`/`jsonDecode` around this map instead (see
  /// `LocalDeviceSettingsRepository`), which stays far more readable than a
  /// hand-rolled delimited string would for this shape.
  Map<String, dynamic> toMap() => {
    'calls': calls.toMap(),
    'quietHours': quietHours.toMap(),
    'confirmBeforeOpeningDoor': confirmBeforeOpeningDoor,
    'requireDeviceAuthenticationToOpenDoor':
        requireDeviceAuthenticationToOpenDoor,
  };

  /// Parses a map produced by [toMap]. Missing/malformed fields fall back to
  /// the same defaults as the default constructor, so a partially corrupted
  /// or older-shaped record never crashes the settings screen.
  factory DeviceSettings.fromMap(Map<String, dynamic> map) {
    return DeviceSettings(
      calls: map['calls'] is Map<String, dynamic>
          ? DeviceCallSettings.fromMap(map['calls'] as Map<String, dynamic>)
          : const DeviceCallSettings(),
      quietHours: map['quietHours'] is Map<String, dynamic>
          ? QuietHoursSettings.fromMap(
              map['quietHours'] as Map<String, dynamic>,
            )
          : const QuietHoursSettings(),
      confirmBeforeOpeningDoor:
          map['confirmBeforeOpeningDoor'] as bool? ?? true,
      requireDeviceAuthenticationToOpenDoor:
          map['requireDeviceAuthenticationToOpenDoor'] as bool? ?? false,
    );
  }
}
