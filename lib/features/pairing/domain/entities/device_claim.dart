/// The two values printed on an InterBridge's QR code, per
/// `docs/communication-protocol.md` §4.
///
/// [deviceId] is not a secret — it's a globally unique but publicly visible
/// identifier. [claimCode] **is** the ownership secret: single-use, must
/// never be persisted in plain text, logged, or sent to analytics/crash
/// reporting. Once a claim succeeds, [claimCode] must be discarded — it is
/// never kept around as a permanent credential; the backend is the one that
/// records ownership after validating it once. Deliberately not just a
/// generic `deviceSecret` field — see PROJECT_CONTEXT.md, "Diferenciando os
/// segredos", for why conflating this with the BLE PoP or Fleet
/// Provisioning material would be a mistake.
class DeviceClaim {
  const DeviceClaim({required this.deviceId, required this.claimCode});

  final String deviceId;
  final String claimCode;

  /// Redacts [claimCode] — a naive `toString()` is a common way secrets
  /// leak into logs/crash reports by accident, so this must never print it.
  @override
  String toString() => 'DeviceClaim(deviceId: $deviceId, claimCode: ***)';
}

/// `ib-` followed by exactly 32 lowercase hexadecimal characters, per
/// `docs/communication-protocol.md` §4.
final RegExp _deviceIdPattern = RegExp(r'^ib-[0-9a-f]{32}$');

/// Parses a scanned QR payload into a [DeviceClaim].
///
/// Expected format (`docs/communication-protocol.md` §4):
///
/// ```text
/// interbridge://claim?v=1&device_id=ib-<32 lowercase hex chars>&claim_code=<secret>
/// ```
///
/// Validates, in order: the URI parses at all; `scheme` is exactly
/// `interbridge`; `host` is exactly `claim`; the required query parameters
/// (`v`, `device_id`, `claim_code`) each appear exactly once — a duplicate
/// makes the whole payload invalid; `v` is exactly `1`; `device_id` matches
/// `^ib-[0-9a-f]{32}$`; `claim_code` is present and non-empty.
///
/// Query values are percent-decoded by [Uri] itself. An escape that isn't
/// valid hex (e.g. `%zz`) is left as literal text by [Uri] rather than
/// rejected; an escape that decodes to invalid UTF-8 (e.g. a lone `%FF`)
/// makes [Uri] throw a [FormatException], which this function catches and
/// treats as an invalid payload. Either way this never throws — returns
/// `null` for anything that fails validation instead, since this runs on
/// arbitrary scanned/pasted input — consistent with
/// `InterBridgeDevice.fromStorage`/`Favorite.fromStorage` elsewhere in this
/// codebase.
DeviceClaim? parseDeviceClaimQrPayload(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  if (uri.scheme != 'interbridge') {
    return null;
  }
  if (uri.host != 'claim') {
    return null;
  }

  Map<String, List<String>> queryParametersAll;
  try {
    queryParametersAll = uri.queryParametersAll;
  } on FormatException {
    // Malformed percent-encoding in a query value.
    return null;
  } on ArgumentError {
    // Dart's percent-decoder throws ArgumentError for some malformed
    // sequences instead of FormatException — treat both the same way.
    return null;
  }

  if (_countOf('v', queryParametersAll) != 1) {
    return null;
  }
  if (_countOf('device_id', queryParametersAll) != 1) {
    return null;
  }
  if (_countOf('claim_code', queryParametersAll) != 1) {
    return null;
  }

  if (queryParametersAll['v']!.single != '1') {
    return null;
  }

  final deviceId = queryParametersAll['device_id']!.single;
  if (!_deviceIdPattern.hasMatch(deviceId)) {
    return null;
  }

  final claimCode = queryParametersAll['claim_code']!.single;
  if (claimCode.isEmpty) {
    return null;
  }

  return DeviceClaim(deviceId: deviceId, claimCode: claimCode);
}

int _countOf(String key, Map<String, List<String>> queryParametersAll) {
  return queryParametersAll[key]?.length ?? 0;
}

/// Outcome of submitting a [DeviceClaim] to the backend claim API.
///
/// This is an **application backend** operation (§6.1: authenticated user +
/// device_id + claim_code → ownership association), not a device MQTT
/// command — it has nothing to do with [DeviceCommandStatus].
enum DeviceClaimStatus {
  claimed,
  invalidClaimCode,
  alreadyOwned,
  backendUnavailable,
}

class DeviceClaimResult {
  const DeviceClaimResult({required this.status, this.deviceId});

  final DeviceClaimStatus status;

  /// Set when [status] is [DeviceClaimStatus.claimed].
  final String? deviceId;
}
