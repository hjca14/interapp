import 'package:interapp/features/devices/domain/entities/intercom_state.dart';

/// Dynamic telemetry received from an InterBridge device.
///
/// This entity is intentionally independent of `InterBridgeDevice`, whose
/// data describes the user's saved device identity.
///
/// Fields are aligned to what the backend can realistically consolidate
/// from AWS IoT (`docs/communication-protocol.md` §22-23), not to raw
/// firmware telemetry: [isOnline] comes from AWS IoT lifecycle/connectivity
/// events, not from [lastSeen] heartbeats, and configuration values that
/// belong to the device's *desired* Device Shadow state (`health_interval_s`
/// etc.) live in `DeviceHardwareConfig` instead — see that file's doc
/// comment and PROJECT_CONTEXT.md, "DeviceSettings vs. Device Shadow
/// config".
class DeviceStatus {
  const DeviceStatus({
    required this.isOnline,
    this.firmwareVersion,
    this.hardwareVersion,
    this.intercomState = IntercomState.unreported,
    this.wifiRssi,
    this.uptime,
    this.isProvisioned,
    this.lastSeen,
    this.hasIncomingCall = false,
    this.errorMessage,
  });

  /// Whether the device is currently reachable, per AWS IoT
  /// lifecycle/connectivity events as consolidated by the backend — never
  /// inferred locally from [lastSeen] alone. The local/prototype
  /// implementation always reports `false`: there's no real hardware to be
  /// online yet, and the UI must not invent an "online" state.
  final bool isOnline;

  final String? firmwareVersion;
  final String? hardwareVersion;

  /// The interfone's reported operating state. Defaults to
  /// [IntercomState.unreported], not a guessed value.
  final IntercomState intercomState;

  /// Wi-Fi signal strength in dBm, as reported in the device's Shadow
  /// (`wifi_rssi`).
  final int? wifiRssi;

  /// Device uptime at the time this status was reported.
  final Duration? uptime;

  /// Whether the device has completed provisioning (`provisioned` in the
  /// reported Shadow state). `null` when unknown.
  final bool? isProvisioned;

  /// Timestamp of the last time the device was heard from.
  final DateTime? lastSeen;

  /// `true` while the interfone is ringing. `IncomingCallListener` watches
  /// this field (via `deviceStatusProvider`) to trigger the local
  /// notification and the full-screen ringing UI — see `IncomingCallPage`.
  final bool hasIncomingCall;

  /// Human-readable error surfaced by the device/transport, if any. This is
  /// a connectivity/status-level message, distinct from a command's
  /// [DeviceProtocolError].
  final String? errorMessage;

  /// Parses a device's *reported* Device Shadow state
  /// (`docs/communication-protocol.md` §22) into a [DeviceStatus].
  ///
  /// [isOnline] and [lastSeen] are passed in separately rather than read
  /// from [reported], because online/offline is authoritatively sourced
  /// from AWS IoT lifecycle events, not from the Shadow document itself
  /// (§23). Unknown extra fields in [reported] are ignored rather than
  /// rejected, per §22 ("Unknown future fields must not crash firmware") —
  /// the same tolerance applies on the app side.
  factory DeviceStatus.fromReportedShadow(
    Map<String, dynamic> reported, {
    required bool isOnline,
    DateTime? lastSeen,
    bool hasIncomingCall = false,
  }) {
    final rawUptimeMs = reported['uptime_ms'];
    return DeviceStatus(
      isOnline: isOnline,
      firmwareVersion: reported['firmware_version'] as String?,
      hardwareVersion: reported['hardware_version'] as String?,
      intercomState: IntercomState.fromRaw(
        reported['intercom_state'] as String?,
      ),
      wifiRssi: (reported['wifi_rssi'] as num?)?.toInt(),
      uptime: rawUptimeMs is num
          ? Duration(milliseconds: rawUptimeMs.toInt())
          : null,
      isProvisioned: reported['provisioned'] as bool?,
      lastSeen: lastSeen,
      hasIncomingCall: hasIncomingCall,
    );
  }
}
