/// Which backend environment the app is built against, per
/// `docs/communication-protocol.md` §11 ("At minimum: DEV, PROD").
///
/// DEV must never be able to authenticate against PROD infrastructure —
/// keeping this as a build-time value (not something toggled at runtime in
/// the UI) is what makes that guarantee possible.
enum AppEnvironment { dev, prod }

/// App-side configuration that varies per [AppEnvironment].
///
/// Deliberately small: the app does not need to know the AWS IoT endpoint,
/// AWS region, or any AWS-specific identifier, because all cloud
/// communication goes through the application backend (see
/// `docs/communication-integration.md`). Only what the app itself calls
/// directly belongs here.
///
/// Values are read from `--dart-define` at build time, never hardcoded —
/// there is intentionally no PROD URL committed to this file. Until a real
/// backend exists, [apiBaseUrl] is empty and callers must treat that as
/// "not configured" rather than defaulting to some guessed address.
class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  final AppEnvironment environment;

  /// Base URL of the AWS application backend's API. Empty when not
  /// configured for this build.
  final String apiBaseUrl;

  bool get isConfigured => apiBaseUrl.isNotEmpty;

  /// Resolves configuration from `--dart-define`d values.
  ///
  /// Example: `flutter run --dart-define=APP_ENVIRONMENT=dev
  /// --dart-define=API_BASE_URL=https://dev.example.com`. With neither
  /// define set (today's normal case, since no backend exists yet), this
  /// resolves to [AppEnvironment.dev] with an empty, "not configured"
  /// [apiBaseUrl].
  factory AppConfig.fromEnvironment() {
    const environmentName = String.fromEnvironment(
      'APP_ENVIRONMENT',
      defaultValue: 'dev',
    );
    return AppConfig(
      environment: environmentName == 'prod'
          ? AppEnvironment.prod
          : AppEnvironment.dev,
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    );
  }
}
