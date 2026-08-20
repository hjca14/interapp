import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/data/repositories/local_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/data/repositories/mock_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/data/repositories/mock_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/data/repositories/not_implemented_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';

/// Debug builds get a working fake so the onboarding flow can be exercised
/// end to end before real BLE exists (PROJECT_CONTEXT.md, "Mock device").
/// Release builds get the honest "not implemented" transport — never the
/// mock, per "Production builds must use the real implementation".
final bleOnboardingTransportProvider = Provider<BleOnboardingTransport>(
  (_) => kDebugMode
      ? MockBleOnboardingTransport()
      : NotImplementedBleOnboardingTransport(),
);

/// Same debug/release split as [bleOnboardingTransportProvider] — see
/// `MockOnboardingClaimRepository`/`LocalOnboardingClaimRepository`.
final onboardingClaimRepositoryProvider = Provider<OnboardingClaimRepository>(
  (_) => kDebugMode
      ? MockOnboardingClaimRepository()
      : LocalOnboardingClaimRepository(),
);

final onboardingAnalyticsProvider = Provider<OnboardingAnalytics>(
  (_) => DebugPrintOnboardingAnalytics(),
);
