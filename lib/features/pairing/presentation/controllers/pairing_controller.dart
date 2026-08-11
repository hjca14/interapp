import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';
import 'package:interapp/features/pairing/domain/entities/provisioning_state.dart';
import 'package:interapp/features/pairing/domain/repositories/provisioning_repository.dart';

/// Drives one onboarding attempt for `PairingPage`.
///
/// Screen-scoped like `DialerController` (created/disposed by the page that
/// uses it), not a Riverpod provider — there's exactly one pairing attempt
/// per screen visit, nothing else in the app needs to observe it.
class PairingController extends ChangeNotifier {
  PairingController(this._repository);

  final ProvisioningRepository _repository;
  ProvisioningState _state = const ProvisioningState();
  StreamSubscription<ProvisioningState>? _subscription;

  ProvisioningState get state => _state;

  /// Starts (or restarts) provisioning. [wifiPassword] is only held by the
  /// caller for the duration of this call and is never stored on this
  /// controller — see `ProvisioningRepository.provision`.
  Future<void> startProvisioning({
    required DeviceClaim claim,
    required String wifiSsid,
    required String wifiPassword,
  }) async {
    await _subscription?.cancel();
    _setState(const ProvisioningState(phase: ProvisioningPhase.scanning));
    _subscription = _repository
        .provision(claim: claim, wifiSsid: wifiSsid, wifiPassword: wifiPassword)
        .listen(_setState);
  }

  void _setState(ProvisioningState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
