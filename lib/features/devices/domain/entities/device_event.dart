import 'package:interapp/core/protocol/protocol_constants.dart';

/// The v1 event vocabulary, per `docs/communication-protocol.md` §16.
///
/// A closed enum plus [unknown]: the protocol fully enumerates this list
/// today, but a future firmware/protocol revision could add to it, and
/// [DeviceEvent.rawType] always preserves the original wire string even
/// when [unknown] so nothing is silently lost.
enum DeviceEventType {
  ringDetected,
  offHook,
  onHook,
  callStarted,
  callEnded,
  doorOpened,
  doorOpenFailed,
  provisioningStarted,
  provisioningCompleted,
  provisioningFailed,
  factoryResetRequested,
  otaStarted,
  otaCompleted,
  otaFailed,
  error,
  unknown;

  static const Map<String, DeviceEventType> _byWireValue = {
    'RING_DETECTED': ringDetected,
    'OFF_HOOK': offHook,
    'ON_HOOK': onHook,
    'CALL_STARTED': callStarted,
    'CALL_ENDED': callEnded,
    'DOOR_OPENED': doorOpened,
    'DOOR_OPEN_FAILED': doorOpenFailed,
    'PROVISIONING_STARTED': provisioningStarted,
    'PROVISIONING_COMPLETED': provisioningCompleted,
    'PROVISIONING_FAILED': provisioningFailed,
    'FACTORY_RESET_REQUESTED': factoryResetRequested,
    'OTA_STARTED': otaStarted,
    'OTA_COMPLETED': otaCompleted,
    'OTA_FAILED': otaFailed,
    'ERROR': error,
  };

  static DeviceEventType fromWireValue(String? value) =>
      _byWireValue[value] ?? unknown;
}

/// One event as reported by an InterBridge through the backend, per §16.
///
/// The app never receives this straight off MQTT/Basic Ingest — the backend
/// relays it through an application API/realtime channel (see
/// `docs/communication-integration.md`). This mirrors the wire shape so
/// parsing/deduplication can be modeled and tested without a real backend.
class DeviceEvent {
  const DeviceEvent({
    required this.eventId,
    required this.deviceId,
    required this.type,
    required this.rawType,
    this.timestamp,
    this.uptime,
  });

  /// Stable id used for deduplication — the protocol delivers events
  /// at-least-once, so the same [eventId] can legitimately arrive twice.
  final String eventId;
  final String deviceId;
  final DeviceEventType type;

  /// The original wire string for [type], preserved even when [type] is
  /// [DeviceEventType.unknown] so a genuinely new event type isn't lost,
  /// just unrecognized.
  final String rawType;

  /// UTC timestamp, when the device had valid wall-clock time to report one
  /// (§14: "do not invent a timestamp").
  final DateTime? timestamp;

  /// Device uptime at the time of the event, when reported.
  final Duration? uptime;

  /// Parses the event envelope shape from §16. Tolerates unknown extra
  /// fields (§33). Throws [UnsupportedProtocolVersionException] when
  /// `protocol_version` is present and isn't [kProtocolVersion] — a version
  /// this app can't safely interpret the rest of the payload for.
  factory DeviceEvent.fromJson(Map<String, dynamic> json) {
    final protocolVersion = (json['protocol_version'] as num?)?.toInt();
    if (protocolVersion != null &&
        !isSupportedProtocolVersion(protocolVersion)) {
      throw UnsupportedProtocolVersionException(protocolVersion);
    }
    final rawType = json['event'] as String?;
    final rawTimestamp = json['timestamp'];
    final rawUptimeMs = json['uptime_ms'];
    return DeviceEvent(
      eventId: json['event_id'] as String,
      deviceId: json['device_id'] as String,
      type: DeviceEventType.fromWireValue(rawType),
      rawType: rawType ?? 'UNKNOWN',
      timestamp: rawTimestamp is String
          ? DateTime.tryParse(rawTimestamp)
          : null,
      uptime: rawUptimeMs is num
          ? Duration(milliseconds: rawUptimeMs.toInt())
          : null,
    );
  }
}

/// Merges [events] keeping only the first occurrence of each
/// [DeviceEvent.eventId] —
/// the protocol delivers events at-least-once (§17: "Backend ingestion must
/// be idempotent by event_id"), so the same event can legitimately arrive
/// twice and consumers must not show/count it twice.
List<DeviceEvent> dedupeDeviceEvents(List<DeviceEvent> events) {
  final seenIds = <String>{};
  final result = <DeviceEvent>[];
  for (final event in events) {
    if (seenIds.add(event.eventId)) {
      result.add(event);
    }
  }
  return result;
}
