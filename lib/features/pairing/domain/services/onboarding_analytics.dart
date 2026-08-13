import 'package:flutter/foundation.dart';

/// Non-sensitive onboarding telemetry, per PROJECT_CONTEXT.md's analytics
/// event list (`onboarding_started`, `ble_scan_started`,
/// `device_discovered`, `device_confirmed`, `ble_connected`,
/// `wifi_config_sent`, `claim_started`, `provisioning_started`,
/// `onboarding_completed`, `onboarding_failed`, `fallback_qr_used`,
/// `fallback_manual_used`).
///
/// [properties] must never include a Wi-Fi password, a full `setup_code`
/// (use `SetupCode.maskedForLogging`), a claim token, or any private key —
/// call sites are responsible for only passing safe values; this
/// abstraction does not scrub them.
abstract class OnboardingAnalytics {
  void track(String event, [Map<String, Object?>? properties]);
}

/// No real analytics provider is wired up yet — this only prints in debug
/// builds so the event stream is visible during development, and does
/// nothing in release builds.
class DebugPrintOnboardingAnalytics implements OnboardingAnalytics {
  @override
  void track(String event, [Map<String, Object?>? properties]) {
    if (kDebugMode) {
      debugPrint('[onboarding-analytics] $event ${properties ?? const {}}');
    }
  }
}
