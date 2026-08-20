/// Backend environment selected at build time.
enum AppEnvironment { dev, prod }

/// Validated configuration needed by Cognito and the InterBridge HTTP API.
///
/// Values are supplied only through `--dart-define`. Missing or malformed
/// values fail startup instead of silently selecting a fictitious backend.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.awsRegion,
    required this.cognitoUserPoolId,
    required this.cognitoAppClientId,
  });

  final AppEnvironment environment;
  final String apiBaseUrl;
  final String awsRegion;
  final String cognitoUserPoolId;
  final String cognitoAppClientId;

  factory AppConfig.fromEnvironment() {
    return AppConfig.fromValues(
      environment: const String.fromEnvironment('APP_ENVIRONMENT'),
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
      awsRegion: const String.fromEnvironment('AWS_REGION'),
      cognitoUserPoolId: const String.fromEnvironment('COGNITO_USER_POOL_ID'),
      cognitoAppClientId: const String.fromEnvironment(
        'COGNITO_APP_CLIENT_ID',
      ),
    );
  }

  /// Validates raw configuration values and normalizes the API URL.
  factory AppConfig.fromValues({
    required String environment,
    required String apiBaseUrl,
    required String awsRegion,
    required String cognitoUserPoolId,
    required String cognitoAppClientId,
  }) {
    final valuesByName = <String, String>{
      'APP_ENVIRONMENT': environment,
      'API_BASE_URL': apiBaseUrl,
      'AWS_REGION': awsRegion,
      'COGNITO_USER_POOL_ID': cognitoUserPoolId,
      'COGNITO_APP_CLIENT_ID': cognitoAppClientId,
    };
    final missingNames = valuesByName.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList();
    if (missingNames.isNotEmpty) {
      throw AppConfigException(
        'Configuração ausente: ${missingNames.join(', ')}. '
        'Informe via --dart-define.',
      );
    }

    final parsedEnvironment = _parseEnvironment(environment);
    final normalizedRegion = awsRegion.trim();
    final normalizedPoolId = cognitoUserPoolId.trim();
    final normalizedClientId = cognitoAppClientId.trim();
    final normalizedApiUrl = _parseAndNormalizeApiUrl(apiBaseUrl);

    if (parsedEnvironment == AppEnvironment.dev &&
        normalizedRegion != 'sa-east-1') {
      throw const AppConfigException('A região de DEV deve ser sa-east-1.');
    }
    if (!normalizedPoolId.startsWith('${normalizedRegion}_')) {
      throw const AppConfigException(
        'COGNITO_USER_POOL_ID não corresponde à região configurada.',
      );
    }

    return AppConfig(
      environment: parsedEnvironment,
      apiBaseUrl: normalizedApiUrl,
      awsRegion: normalizedRegion,
      cognitoUserPoolId: normalizedPoolId,
      cognitoAppClientId: normalizedClientId,
    );
  }

  static AppEnvironment _parseEnvironment(String value) {
    return switch (value.trim().toLowerCase()) {
      'dev' => AppEnvironment.dev,
      'prod' => AppEnvironment.prod,
      _ => throw const AppConfigException(
        'APP_ENVIRONMENT deve ser dev ou prod.',
      ),
    };
  }

  static String _parseAndNormalizeApiUrl(String value) {
    final trimmedValue = value.trim();
    final uri = Uri.tryParse(trimmedValue);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const AppConfigException(
        'API_BASE_URL deve ser uma URL HTTPS válida, sem query ou fragmento.',
      );
    }
    return trimmedValue.replaceFirst(RegExp(r'/+$'), '');
  }
}

/// Safe configuration failure suitable for display during app bootstrap.
class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
