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
