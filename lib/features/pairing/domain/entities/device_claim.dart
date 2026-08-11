import 'dart:convert';

/// The two values printed on an InterBridge's QR code, per
/// `docs/communication-protocol.md` §4.
///
/// [deviceId] is not a secret — it's a globally unique but publicly visible
/// identifier. [claimCode] **is** the ownership secret: single-use, must
/// never be persisted in plain text, logged, or sent to analytics/crash
/// reporting, and must be discarded once the claim flow completes
/// (successfully or not). Deliberately not just a generic `deviceSecret`
/// field — see PROJECT_CONTEXT.md, "Diferenciando os segredos", for why
/// conflating this with the BLE PoP or Fleet Provisioning material would be
/// a mistake.
class DeviceClaim {
  const DeviceClaim({required this.deviceId, required this.claimCode});

  final String deviceId;
  final String claimCode;

  /// Redacts [claimCode] — a naive `toString()` is a common way secrets
  /// leak into logs/crash reports by accident, so this must never print it.
  @override
  String toString() => 'DeviceClaim(deviceId: $deviceId, claimCode: ***)';
}

/// Parses a scanned QR payload into a [DeviceClaim].
///
/// The exact text encoding of the QR isn't specified by
/// `docs/communication-protocol.md` (§4 only says it contains `device_id`
/// and `claim_code`) — this assumes a JSON object with those two keys as a
/// placeholder. Confirm the real encoding with firmware/ops before wiring
/// up an actual QR scanner package (see PROJECT_CONTEXT.md, open
/// decisions). Returns `null` for anything that doesn't parse instead of
/// throwing, since this runs on arbitrary scanned/pasted input.
DeviceClaim? parseDeviceClaimQrPayload(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final deviceId = decoded['device_id'];
  final claimCode = decoded['claim_code'];
  if (deviceId is! String || deviceId.isEmpty) return null;
  if (claimCode is! String || claimCode.isEmpty) return null;
  return DeviceClaim(deviceId: deviceId, claimCode: claimCode);
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
