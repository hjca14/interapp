import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/auth/domain/repositories/auth_repository.dart';
import 'api_failure.dart';

/// Small authenticated JSON client restricted to the InterBridge API.
///
/// Every request obtains a valid Cognito access token. A 401 causes exactly
/// one forced refresh and one retry; a second 401 invalidates the local session
/// so routing can return to login. Tokens and response bodies are never logged.
class InterBridgeApiClient {
  InterBridgeApiClient({
    required this.baseUrl,
    required AuthRepository auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _auth = auth,
       _client = client ?? http.Client();

  final String baseUrl;
  final AuthRepository _auth;
  final http.Client _client;
  final Duration timeout;

  /// Performs a GET and returns a JSON object response.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final firstResponse = await _sendGet(path, query: query);
    if (firstResponse.statusCode != HttpStatus.unauthorized) {
      return _decodeSuccessfulResponse(firstResponse);
    }

    // Refresh and retry are deliberately bounded to prevent authorization
    // loops. Amplify performs the refresh securely; the app never handles the
    // refresh token itself.
    final retryResponse = await _sendGet(
      path,
      query: query,
      forceRefresh: true,
    );
    if (retryResponse.statusCode == HttpStatus.unauthorized) {
      await _auth.invalidateSession();
      throw const ApiFailure(
        ApiFailureKind.unauthorized,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    return _decodeSuccessfulResponse(retryResponse);
  }

  Future<http.Response> _sendGet(
    String path, {
    Map<String, String>? query,
    bool forceRefresh = false,
  }) async {
    final accessToken = await _auth.getValidAccessToken(
      forceRefresh: forceRefresh,
    );
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      return await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(
        ApiFailureKind.timeout,
        'O serviço demorou para responder.',
      );
    } on SocketException {
      throw const ApiFailure(
        ApiFailureKind.offline,
        'Sem conexão com o serviço.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        ApiFailureKind.offline,
        'Sem conexão com o serviço.',
      );
    }
  }

  Map<String, dynamic> _decodeSuccessfulResponse(http.Response response) {
    final requestId = response.headers['x-request-id'];
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      throw _mapStatusFailure(response, requestId);
    }

    final Object? decodedJson;
    try {
      decodedJson = jsonDecode(response.body);
    } on FormatException {
      throw ApiFailure(
        ApiFailureKind.invalidResponse,
        'A resposta do serviço é inválida.',
        requestId: requestId,
      );
    }
    if (decodedJson is! Map<String, dynamic>) {
      throw ApiFailure(
        ApiFailureKind.invalidResponse,
        'A resposta do serviço é incompatível.',
        requestId: requestId,
      );
    }
    return decodedJson;
  }

  ApiFailure _mapStatusFailure(http.Response response, String? requestId) {
    return switch (response.statusCode) {
      HttpStatus.badRequest => ApiFailure(
        ApiFailureKind.badRequest,
        'A solicitação é inválida.',
        requestId: requestId,
      ),
      HttpStatus.notFound => ApiFailure(
        ApiFailureKind.notFound,
        'Recurso indisponível.',
        requestId: requestId,
      ),
      429 => ApiFailure(
        ApiFailureKind.rateLimited,
        'Muitas solicitações. Tente mais tarde.',
        requestId: requestId,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      ),
      HttpStatus.internalServerError => ApiFailure(
        ApiFailureKind.server,
        'O serviço encontrou um erro.',
        requestId: requestId,
      ),
      HttpStatus.serviceUnavailable => ApiFailure(
        ApiFailureKind.unavailable,
        'Serviço temporariamente indisponível.',
        requestId: requestId,
      ),
      _ => ApiFailure(
        ApiFailureKind.invalidResponse,
        'Resposta inesperada do serviço.',
        requestId: requestId,
      ),
    };
  }

  static Duration? _parseRetryAfter(String? headerValue) {
    final seconds = int.tryParse(headerValue ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
