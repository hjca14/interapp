import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

/// The onboarding/provisioning state machine, per
/// `docs/communication-protocol.md` §7 and §6.1.
///
/// Mirrors the protocol's provisioning lifecycle diagram step for step, so
/// [PairingController]/`PairingPage` can show progress without scattering
/// ad hoc callbacks across the BLE/Fleet Provisioning layers.
enum ProvisioningPhase {
  idle,
  scanning,
  deviceFound,
  establishingSecureSession,
  awaitingWifi,
  sendingWifi,
  requestingCloudClaim,
  transferringFleetProvisioningMaterial,
  waitingForDeviceWifi,
  waitingForFleetProvisioning,
  waitingForCloudConnection,
  completed,
  failed;

  bool get isInProgress => this != idle && this != completed && this != failed;
}

class ProvisioningState {
  const ProvisioningState({
    this.phase = ProvisioningPhase.idle,
    this.deviceId,
    this.error,
    this.failureReason,
  });

  final ProvisioningPhase phase;

  /// Known once [ProvisioningPhase.deviceFound] or later.
  final String? deviceId;

  /// Set when [phase] is [ProvisioningPhase.failed] and the failure maps to
  /// a known protocol error.
  final DeviceProtocolError? error;

  /// Set when [phase] is [ProvisioningPhase.failed] for a reason outside
  /// the device protocol itself (e.g. "BLE provisioning not implemented
  /// yet" for the current stub transport).
  final String? failureReason;

  ProvisioningState copyWith({
    ProvisioningPhase? phase,
    String? deviceId,
    DeviceProtocolError? error,
    String? failureReason,
  }) {
    return ProvisioningState(
      phase: phase ?? this.phase,
      deviceId: deviceId ?? this.deviceId,
      error: error ?? this.error,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
