import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/data/repositories/android_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/data/repositories/ios_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/data/repositories/local_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/data/repositories/not_implemented_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';

/// The prototype remains navigable, but never pretends BLE provisioning is
/// available in an application build.
const _developmentBlePop = String.fromEnvironment('INTERBRIDGE_BLE_DEV_POP');

/// Picks the real per-platform [BleOnboardingTransport], or the honest
/// unavailable stand-in — a pure function of [platform]/[developmentPop] so
/// the selection itself is testable without depending on the
/// compile-time-only `--dart-define` that feeds [_developmentBlePop] in the
/// actual provider below. Android and iOS are the only platforms with a real
/// implementation; every other platform (and a missing PoP, on any platform)
/// falls back to [NotImplementedBleOnboardingTransport].
BleOnboardingTransport selectBleOnboardingTransport({
  required TargetPlatform platform,
  required String developmentPop,
}) {
  if (developmentPop.isEmpty) {
    return NotImplementedBleOnboardingTransport();
  }
  return switch (platform) {
    TargetPlatform.android => AndroidBleOnboardingTransport(
      developmentProofOfPossession: developmentPop,
    ),
    TargetPlatform.iOS => IOSBleOnboardingTransport(
      developmentProofOfPossession: developmentPop,
    ),
    _ => NotImplementedBleOnboardingTransport(),
  };
}

final bleOnboardingTransportProvider = Provider<BleOnboardingTransport>(
  (_) => selectBleOnboardingTransport(
    platform: defaultTargetPlatform,
    developmentPop: _developmentBlePop,
  ),
);

/// Claim is intentionally unavailable until the application backend exposes
/// the real flow. Tests can still override this seam with scenario fakes.
final onboardingClaimRepositoryProvider = Provider<OnboardingClaimRepository>(
  (_) => LocalOnboardingClaimRepository(),
);

final onboardingAnalyticsProvider = Provider<OnboardingAnalytics>(
  (_) => DebugPrintOnboardingAnalytics(),
);
