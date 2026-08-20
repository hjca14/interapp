import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/data/repositories/local_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/data/repositories/not_implemented_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';

/// The prototype remains navigable, but never pretends BLE provisioning is
/// available in an application build.
final bleOnboardingTransportProvider = Provider<BleOnboardingTransport>(
  (_) => NotImplementedBleOnboardingTransport(),
);

/// Claim is intentionally unavailable until the application backend exposes
/// the real flow. Tests can still override this seam with scenario fakes.
final onboardingClaimRepositoryProvider = Provider<OnboardingClaimRepository>(
  (_) => LocalOnboardingClaimRepository(),
);

final onboardingAnalyticsProvider = Provider<OnboardingAnalytics>(
  (_) => DebugPrintOnboardingAnalytics(),
);
