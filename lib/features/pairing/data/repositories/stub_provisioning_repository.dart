import 'package:interapp/features/pairing/domain/entities/device_claim.dart';
import 'package:interapp/features/pairing/domain/entities/provisioning_state.dart';
import 'package:interapp/features/pairing/domain/repositories/provisioning_repository.dart';

/// Temporary implementation used until a real BLE/ESP-IDF Unified
/// Provisioning transport is validated and wired in.
///
/// Honestly reports that BLE provisioning isn't implemented instead of
/// hanging forever or pretending to succeed — `PairingPage` can exercise
/// the whole [ProvisioningState] flow (and its own loading/failure UI)
/// against this today.
class StubProvisioningRepository implements ProvisioningRepository {
  @override
  Stream<ProvisioningState> provision({
    required DeviceClaim claim,
    required String wifiSsid,
    required String wifiPassword,
  }) async* {
    yield const ProvisioningState(phase: ProvisioningPhase.scanning);
    yield ProvisioningState(
      phase: ProvisioningPhase.deviceFound,
      deviceId: claim.deviceId,
    );
    yield const ProvisioningState(
      phase: ProvisioningPhase.failed,
      failureReason:
          'Pareamento por Bluetooth ainda não foi implementado neste app.',
    );
  }
}
