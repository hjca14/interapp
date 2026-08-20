import '../../../sharing/domain/entities/device_access.dart';
import 'intercom_state.dart';

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
  final String? displayName;
  final DeviceRole role;
  final MembershipStatus status;

  /// Friendly fallback that reveals only a short distinguishing suffix.
  String get safeName {
    if (displayName != null) {
      return displayName!;
    }
    final suffixStart = deviceId.length > 4 ? deviceId.length - 4 : 0;
    return 'Meu InterBridge •${deviceId.substring(suffixStart)}';
  }
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
