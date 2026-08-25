import '../entities/api_device.dart';

/// Directory of the current user's InterBridge devices: list, details, and
/// the authenticated user's personal-name edit. Deliberately excludes
/// `status()` (connectivity
/// polling stays its own concern, see `apiDeviceStatusProvider`) and every
/// other device capability (BLE, onboarding, sharing, history) — those are
/// out of scope for this contract and have their own repositories.
///
/// [HttpDeviceRepository] implements this against interBackend. The rename
/// contract is confirmed by interBackend PR #18, although its implementation
/// has not yet been deployed to AWS or validated through a real remote call.
abstract class DeviceRepository {
  /// Gets a page of device memberships accessible to the current user.
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor});

  /// Gets device details by ID.
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId);

  /// Sets the authenticated user's personal name for the device, or clears it
  /// (falling back to "InterBridge") when [displayName] is `null`. This does
  /// not change the name seen by other memberships. Implementations must not
  /// treat an empty string as a clear signal — callers are expected to pass
  /// `null` explicitly for that, and a non-null value is expected to already
  /// be trimmed and non-empty. Returns the updated device details as
  /// confirmed by the backend.
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  );
}
