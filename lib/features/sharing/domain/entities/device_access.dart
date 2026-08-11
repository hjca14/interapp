/// A user's level of access to a shared device.
///
/// `owner`: registered/removed/shared the device, manages other users'
/// access. `admin`: manages the device and favorites per granted
/// permissions. `member`: uses the device per granted permissions.
///
/// Sharing itself isn't implemented yet — this models the shape for when it
/// is (Fase 4).
enum DeviceRole { owner, admin, member }

/// Defines a user's future access to an InterBridge device.
class DeviceAccess {
  const DeviceAccess({
    required this.deviceId,
    required this.userId,
    required this.role,
  });

  final String deviceId;
  final String userId;
  final DeviceRole role;
}
