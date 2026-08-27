/// Local, installation-specific door preferences.
///
/// Alert preferences deliberately live in [DeviceNotificationPreferences]
/// and are never serialized here. Unknown legacy keys are ignored by
/// [fromMap], so old installations retain their door choices without
/// uploading experimental call or quiet-hour values.
class DeviceSettings {
  const DeviceSettings({
    this.confirmBeforeOpeningDoor = true,
    this.requireDeviceAuthenticationToOpenDoor = false,
  });

  final bool confirmBeforeOpeningDoor;
  final bool requireDeviceAuthenticationToOpenDoor;

  DeviceSettings copyWith({
    bool? confirmBeforeOpeningDoor,
    bool? requireDeviceAuthenticationToOpenDoor,
  }) => DeviceSettings(
    confirmBeforeOpeningDoor:
        confirmBeforeOpeningDoor ?? this.confirmBeforeOpeningDoor,
    requireDeviceAuthenticationToOpenDoor:
        requireDeviceAuthenticationToOpenDoor ??
        this.requireDeviceAuthenticationToOpenDoor,
  );

  Map<String, dynamic> toMap() => {
    'confirmBeforeOpeningDoor': confirmBeforeOpeningDoor,
    'requireDeviceAuthenticationToOpenDoor':
        requireDeviceAuthenticationToOpenDoor,
  };

  factory DeviceSettings.fromMap(Map<String, dynamic> map) {
    final confirm = map['confirmBeforeOpeningDoor'];
    final authentication = map['requireDeviceAuthenticationToOpenDoor'];
    return DeviceSettings(
      confirmBeforeOpeningDoor: confirm is bool ? confirm : true,
      requireDeviceAuthenticationToOpenDoor: authentication is bool
          ? authentication
          : false,
    );
  }
}
