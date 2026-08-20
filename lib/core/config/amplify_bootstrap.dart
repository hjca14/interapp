import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import 'app_environment.dart';

/// Configures the official Cognito plugin exactly once for this process.
class AmplifyBootstrap {
  static Future<void>? _initialization;

  static Future<void> configure(AppConfig config) {
    return _initialization ??= _configure(config);
  }

  static Future<void> _configure(AppConfig config) async {
    if (Amplify.isConfigured) {
      return;
    }

    await Amplify.addPlugin(AmplifyAuthCognito());
    await Amplify.configure(jsonEncode(_buildConfiguration(config)));
  }

  static Map<String, Object> _buildConfiguration(AppConfig config) {
    return {
      'UserAgent': 'interapp',
      'Version': '1.0',
      'auth': {
        'plugins': {
          'awsCognitoAuthPlugin': {
            'UserAgent': 'interapp',
            'Version': '1.0',
            'IdentityManager': {'Default': <String, Object>{}},
            'CognitoUserPool': {
              'Default': {
                'PoolId': config.cognitoUserPoolId,
                'AppClientId': config.cognitoAppClientId,
                'Region': config.awsRegion,
              },
            },
            'Auth': {
              'Default': {'authenticationFlowType': 'USER_SRP_AUTH'},
            },
          },
        },
      },
    };
  }
}
