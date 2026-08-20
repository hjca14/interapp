import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/config/app_environment.dart';

void main() {
  AppConfig createValidConfig() {
    return AppConfig.fromValues(
      environment: 'dev',
      apiBaseUrl: 'https://api.example.invalid/',
      awsRegion: 'sa-east-1',
      cognitoUserPoolId: 'sa-east-1_PLACEHOLDER',
      cognitoAppClientId: 'PLACEHOLDER',
    );
  }

  test('validates and normalizes DEV configuration', () {
    expect(createValidConfig().apiBaseUrl, 'https://api.example.invalid');
  });

  const requiredFields = [
    'environment',
    'apiBaseUrl',
    'awsRegion',
    'cognitoUserPoolId',
    'cognitoAppClientId',
  ];
  for (final missingField in requiredFields) {
    test('rejects missing $missingField', () {
      final values = <String, String>{
        'environment': 'dev',
        'apiBaseUrl': 'https://api.example.invalid',
        'awsRegion': 'sa-east-1',
        'cognitoUserPoolId': 'sa-east-1_PLACEHOLDER',
        'cognitoAppClientId': 'PLACEHOLDER',
      };
      values[missingField] = '';

      expect(
        () => AppConfig.fromValues(
          environment: values['environment']!,
          apiBaseUrl: values['apiBaseUrl']!,
          awsRegion: values['awsRegion']!,
          cognitoUserPoolId: values['cognitoUserPoolId']!,
          cognitoAppClientId: values['cognitoAppClientId']!,
        ),
        throwsA(isA<AppConfigException>()),
      );
    });
  }

  test('rejects HTTP API URL', () {
    expect(
      () => AppConfig.fromValues(
        environment: 'dev',
        apiBaseUrl: 'http://example.invalid',
        awsRegion: 'sa-east-1',
        cognitoUserPoolId: 'sa-east-1_PLACEHOLDER',
        cognitoAppClientId: 'PLACEHOLDER',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('rejects divergent DEV region', () {
    expect(
      () => AppConfig.fromValues(
        environment: 'dev',
        apiBaseUrl: 'https://example.invalid',
        awsRegion: 'us-east-1',
        cognitoUserPoolId: 'us-east-1_PLACEHOLDER',
        cognitoAppClientId: 'PLACEHOLDER',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });
}
