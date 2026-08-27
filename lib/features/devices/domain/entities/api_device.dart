import '../../../sharing/domain/entities/device_access.dart';
import 'intercom_state.dart';

/// Confirmed maximum length for the authenticated user's personal device name.
const int kDeviceDisplayNameMaxLength = 60;

/// The single fallback used everywhere a device's name is shown, so no
/// screen invents its own wording and no screen ever falls back to showing
/// `device_id`. Returns [displayName] trimmed when it is a real custom name,
/// or the literal "InterBridge" when it is null, empty, or whitespace-only
/// (including the empty string some older records may still hold).
String deviceDisplayName(String? displayName) {
  final trimmed = displayName?.trim();
  return trimmed == null || trimmed.isEmpty ? 'InterBridge' : trimmed;
}

/// Best currently-known display name for a device given a possibly
/// still-loading detail read (e.g. `apiDeviceDetailProvider`) and, as a
/// fallback, a name already known from elsewhere (e.g. the paginated device
/// list). Returns `null` only when nothing is known yet, so a caller can
/// render its own neutral loading title instead of ever treating
/// "InterBridge" as if it were the device's confirmed name during a
/// transient load — see [deviceDisplayName], which is only safe to apply
/// once [detailLoaded] is true.
String? resolveKnownDeviceName({
  required bool detailLoaded,
  String? confirmedDisplayName,
  String? knownDisplayName,
}) {
  if (detailLoaded) return deviceDisplayName(confirmedDisplayName);
  final known = knownDisplayName?.trim();
  return known == null || known.isEmpty ? null : known;
}

/// Membership status returned by the deployed list endpoint.
enum MembershipStatus { active }

/// Backend-authoritative device connectivity classification.
enum DeviceConnectivity { recentlySeen, stale, unknown }

/// Freshness classification for the current status representation.
enum DeviceFreshness { fresh, stale, unknown }

/// One device membership returned by the list endpoint.
class ApiDeviceSummary {
  const ApiDeviceSummary({
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String deviceId;

  /// Personal name from the authenticated user's `DeviceMembership`.
  ///
  /// This is not a physical/global property of the device. Updating it does
  /// not change the name returned to other users.
  final String? displayName;
  final DeviceRole role;
  final MembershipStatus status;

  /// Friendly name for display, never `device_id`. See [deviceDisplayName].
  String get safeName => deviceDisplayName(displayName);
}

/// A page from the device-list endpoint with an opaque continuation cursor.
class ApiDevicePage {
  const ApiDevicePage({required this.items, this.nextCursor});

  final List<ApiDeviceSummary> items;
  final String? nextCursor;
}

/// Read-only device details returned by the backend.
class ApiDeviceDetail {
  const ApiDeviceDetail({
    required this.deviceId,
    this.displayName,
    this.hardwareVersion,
    required this.ownershipStatus,
    required this.provisioningStatus,
    required this.role,
  });

  final String deviceId;

  /// Personal name from the authenticated user's `DeviceMembership`.
  ///
  /// This is not a physical/global property of the device. Updating it does
  /// not change the name returned to other users.
  final String? displayName;
  final String? hardwareVersion;
  final String ownershipStatus;
  final String provisioningStatus;
  final DeviceRole role;
}

/// Optional telemetry nested in [ApiDeviceStatus].
class ApiDeviceHealth {
  const ApiDeviceHealth({
    required this.intercomState,
    required this.firmwareVersion,
    required this.lastSeenAt,
  });

  final IntercomState intercomState;
  final String firmwareVersion;
  final DateTime lastSeenAt;
}

/// Current status returned separately from device identity/details.
class ApiDeviceStatus {
  const ApiDeviceStatus({
    required this.deviceId,
    required this.connectivity,
    required this.freshness,
    this.health,
  });

  final String deviceId;
  final DeviceConnectivity connectivity;
  final DeviceFreshness freshness;

  /// Null means the backend has no health report; the app must not fabricate
  /// firmware, intercom state, or last-seen values in that case.
  final ApiDeviceHealth? health;
}
