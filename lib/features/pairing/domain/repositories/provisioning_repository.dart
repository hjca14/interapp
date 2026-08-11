import 'package:interapp/features/pairing/domain/entities/device_claim.dart';
import 'package:interapp/features/pairing/domain/entities/provisioning_state.dart';

/// Orchestrates onboarding a new InterBridge: BLE provisioning, Wi-Fi
/// handoff and AWS Fleet Provisioning, per
/// `docs/communication-protocol.md` §6.1/§7.
///
/// A single `Stream<ProvisioningState>` instead of scattered callbacks, so
/// `PairingController`/`PairingPage` can show progress from one source of
/// truth. Implementations sit on top of a [ProvisioningTransport] for the
/// BLE parts and the application backend for the cloud-claim part.
abstract class ProvisioningRepository {
  /// Runs the full onboarding flow for [claim]. [wifiSsid]/[wifiPassword]
  /// are only ever held in memory for the duration of this call — per §7,
  /// Wi-Fi credentials must only cross the secure BLE provisioning channel,
  /// never `shared_preferences`, `DeviceSettings`, logs, or a normal API
  /// call.
  Stream<ProvisioningState> provision({
    required DeviceClaim claim,
    required String wifiSsid,
    required String wifiPassword,
  });
}
