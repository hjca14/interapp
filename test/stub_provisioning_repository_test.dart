import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/pairing/data/repositories/stub_provisioning_repository.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';
import 'package:interapp/features/pairing/domain/entities/provisioning_state.dart';

void main() {
  group('StubProvisioningRepository', () {
    test(
      'emits scanning, then deviceFound, then an honest failed state',
      () async {
        final repository = StubProvisioningRepository();
        const claim = DeviceClaim(deviceId: 'ib-abc123', claimCode: 'secret');

        final states = await repository
            .provision(
              claim: claim,
              wifiSsid: 'home-network',
              wifiPassword: 'irrelevant',
            )
            .toList();

        expect(states.map((s) => s.phase), [
          ProvisioningPhase.scanning,
          ProvisioningPhase.deviceFound,
          ProvisioningPhase.failed,
        ]);
        expect(states.last.failureReason, isNotNull);
        expect(states.last.error, DeviceProtocolError.provisioningFailed);
      },
    );

    test('carries the claimed device_id once found', () async {
      final repository = StubProvisioningRepository();
      const claim = DeviceClaim(deviceId: 'ib-abc123', claimCode: 'secret');

      final states = await repository
          .provision(
            claim: claim,
            wifiSsid: 'home-network',
            wifiPassword: 'irrelevant',
          )
          .toList();

      final found = states.firstWhere(
        (s) => s.phase == ProvisioningPhase.deviceFound,
      );
      expect(found.deviceId, 'ib-abc123');
    });

    test(
      'never reports completed — it has no real transport to complete with',
      () async {
        final repository = StubProvisioningRepository();
        const claim = DeviceClaim(deviceId: 'ib-abc123', claimCode: 'secret');

        final states = await repository
            .provision(
              claim: claim,
              wifiSsid: 'home-network',
              wifiPassword: 'irrelevant',
            )
            .toList();

        expect(
          states.any((s) => s.phase == ProvisioningPhase.completed),
          isFalse,
        );
      },
    );
  });

  group('ProvisioningPhase.isInProgress', () {
    test('idle, completed and failed are not in-progress', () {
      expect(ProvisioningPhase.idle.isInProgress, isFalse);
      expect(ProvisioningPhase.completed.isInProgress, isFalse);
      expect(ProvisioningPhase.failed.isInProgress, isFalse);
    });

    test('every other phase is in-progress', () {
      const inProgressPhases = {
        ProvisioningPhase.scanning,
        ProvisioningPhase.deviceFound,
        ProvisioningPhase.establishingSecureSession,
        ProvisioningPhase.awaitingWifi,
        ProvisioningPhase.sendingWifi,
        ProvisioningPhase.requestingCloudClaim,
        ProvisioningPhase.transferringFleetProvisioningMaterial,
        ProvisioningPhase.waitingForDeviceWifi,
        ProvisioningPhase.waitingForFleetProvisioning,
        ProvisioningPhase.waitingForCloudConnection,
      };
      for (final phase in inProgressPhases) {
        expect(
          phase.isInProgress,
          isTrue,
          reason: '$phase should be in-progress',
        );
      }
    });
  });
}
