import '../network/interbridge_api_client.dart';

abstract interface class PushInstallationRepository {
  Future<void> registerInstallation({
    required String installationId,
    required String token,
    required String appVersion,
  });
  Future<void> deleteInstallation(String installationId);
}

class HttpPushInstallationRepository implements PushInstallationRepository {
  HttpPushInstallationRepository(this._client);
  final InterBridgeApiClient _client;

  @override
  Future<void> registerInstallation({
    required String installationId,
    required String token,
    required String appVersion,
  }) => _client.putEmpty(
    '/v1/push/installations/${Uri.encodeComponent(installationId)}',
    body: {
      'version': 1,
      'platform': 'ANDROID',
      'push_provider': 'FCM',
      'token': token,
      'app_id': 'com.interbridge.app',
      'app_version': appVersion,
    },
  );

  @override
  Future<void> deleteInstallation(String installationId) => _client.deleteEmpty(
    '/v1/push/installations/${Uri.encodeComponent(installationId)}',
  );
}
