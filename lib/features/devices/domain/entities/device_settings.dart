/// Local, installation-specific door preferences.
///
/// Alert preferences deliberately live in [DeviceNotificationPreferences]
/// and are never serialized here. Unknown legacy keys are ignored by
/// [fromMap], so old installations retain their door choices without
/// uploading experimental call or quiet-hour values.
class DeviceSettings {
  const DeviceSettings({
    this.doorOpeningEnabled = false,
    this.confirmBeforeOpeningDoor = true,
    this.requireDeviceAuthenticationToOpenDoor = false,
  });

  /// Controls only whether this installation presents the door-opening UI.
  /// It neither disables the physical relay nor changes backend authorization.
  final bool doorOpeningEnabled;
  final bool confirmBeforeOpeningDoor;
  final bool requireDeviceAuthenticationToOpenDoor;

  DeviceSettings copyWith({
    bool? doorOpeningEnabled,
    bool? confirmBeforeOpeningDoor,
    bool? requireDeviceAuthenticationToOpenDoor,
  }) => DeviceSettings(
    doorOpeningEnabled: doorOpeningEnabled ?? this.doorOpeningEnabled,
    confirmBeforeOpeningDoor:
        confirmBeforeOpeningDoor ?? this.confirmBeforeOpeningDoor,
    requireDeviceAuthenticationToOpenDoor:
        requireDeviceAuthenticationToOpenDoor ??
        this.requireDeviceAuthenticationToOpenDoor,
  );

  Map<String, dynamic> toMap() => {
    'doorOpeningEnabled': doorOpeningEnabled,
    'confirmBeforeOpeningDoor': confirmBeforeOpeningDoor,
    'requireDeviceAuthenticationToOpenDoor':
        requireDeviceAuthenticationToOpenDoor,
  };

  factory DeviceSettings.fromMap(Map<String, dynamic> map) {
    final enabled = map['doorOpeningEnabled'];
    final confirm = map['confirmBeforeOpeningDoor'];
    final authentication = map['requireDeviceAuthenticationToOpenDoor'];
    return DeviceSettings(
      doorOpeningEnabled: enabled is bool ? enabled : false,
      confirmBeforeOpeningDoor: confirm is bool ? confirm : true,
      requireDeviceAuthenticationToOpenDoor: authentication is bool
          ? authentication
          : false,
    );
  }
}
