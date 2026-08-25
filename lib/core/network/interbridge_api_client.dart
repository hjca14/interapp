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
    required this._auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : // ignore: prefer_initializing_formals
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

  /// Performs an authenticated JSON POST using the same auth and refresh path
  /// as every other API request. Header values are deliberately never logged.
  Future<Map<String, dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String> headers = const {},
    int expectedStatus = HttpStatus.ok,
  }) async {
    final first = await _sendPost(path, body: body, headers: headers);
    if (first.statusCode != HttpStatus.unauthorized) {
      return _decodeResponse(first, expectedStatus: expectedStatus);
    }
    final retry = await _sendPost(
      path,
      body: body,
      headers: headers,
      forceRefresh: true,
    );
    if (retry.statusCode == HttpStatus.unauthorized) {
      await _auth.invalidateSession();
      throw const ApiFailure(
        ApiFailureKind.unauthorized,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    return _decodeResponse(retry, expectedStatus: expectedStatus);
  }

  /// Performs an authenticated JSON PATCH using the same auth and refresh
  /// path as every other API request.
  Future<Map<String, dynamic>> patch(
    String path, {
    required Map<String, dynamic> body,
    int expectedStatus = HttpStatus.ok,
  }) async {
    final first = await _sendPatch(path, body: body);
    if (first.statusCode != HttpStatus.unauthorized) {
      return _decodeResponse(first, expectedStatus: expectedStatus);
    }
    final retry = await _sendPatch(path, body: body, forceRefresh: true);
    if (retry.statusCode == HttpStatus.unauthorized) {
      await _auth.invalidateSession();
      throw const ApiFailure(
        ApiFailureKind.unauthorized,
        'Sua sessão expirou. Entre novamente.',
      );
    }
    return _decodeResponse(retry, expectedStatus: expectedStatus);
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
      return await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
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

  Future<http.Response> _sendPost(
    String path, {
    required Map<String, dynamic> body,
    required Map<String, String> headers,
    bool forceRefresh = false,
  }) async {
    final accessToken = await _auth.getValidAccessToken(
      forceRefresh: forceRefresh,
    );
    try {
      return await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
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

  Future<http.Response> _sendPatch(
    String path, {
    required Map<String, dynamic> body,
    bool forceRefresh = false,
  }) async {
    final accessToken = await _auth.getValidAccessToken(
      forceRefresh: forceRefresh,
    );
    try {
      return await _client
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
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
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    int? expectedStatus,
  }) {
    final requestId = response.headers['x-request-id'];
    if (expectedStatus != null
        ? response.statusCode != expectedStatus
        : response.statusCode < HttpStatus.ok ||
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
      HttpStatus.unauthorized => ApiFailure(
        ApiFailureKind.unauthorized,
        'Sua sessão expirou. Entre novamente.',
        requestId: requestId,
      ),
      HttpStatus.forbidden => ApiFailure(
        ApiFailureKind.forbidden,
        'Você não tem permissão para esta ação.',
        requestId: requestId,
      ),
      HttpStatus.notFound => ApiFailure(
        ApiFailureKind.notFound,
        'Recurso indisponível.',
        requestId: requestId,
      ),
      HttpStatus.conflict => ApiFailure(
        ApiFailureKind.conflict,
        'A tentativa conflita com uma solicitação anterior.',
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
    if (seconds == null || seconds < 0) {
      return null;
    }
    return Duration(seconds: seconds.clamp(0, 30));
  }
}
