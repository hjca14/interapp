/// Hardware-facing desired configuration — the values that would live in
/// the InterBridge's named Device Shadow (`interbridge`) `desired` state,
/// per `docs/communication-protocol.md` §22.
///
/// Deliberately **not** part of `DeviceSettings`: those are app/user
/// preferences such as local door confirmation (remote alert preferences live
/// in `DeviceNotificationPreferences`), while this is configuration the
/// *device itself* would apply
/// (e.g. how long to hold the door relay open). See PROJECT_CONTEXT.md,
/// "DeviceSettings vs. Device Shadow config", for the full reasoning.
///
/// Not synced to any backend yet — this only reserves the shape so the two
/// concepts don't get mixed together once syncing is implemented.
class DeviceHardwareConfig {
  const DeviceHardwareConfig({
    this.healthIntervalSeconds,
    this.ringTimeoutMs,
    this.doorOpenDurationMs,
    this.audioVolume,
  });

  final int? healthIntervalSeconds;
  final int? ringTimeoutMs;
  final int? doorOpenDurationMs;
  final int? audioVolume;
}
