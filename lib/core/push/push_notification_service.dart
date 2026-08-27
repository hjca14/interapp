import 'dart:async';

import 'package:flutter/foundation.dart';

import 'push_message.dart';
import 'push_messaging_client.dart';

/// App-facing seam for FCM: permission, token and message streams.
///
/// The UI and other features must go through this service instead of
/// touching `FirebaseMessaging.instance` directly. No failure here is
/// allowed to escape — a broken Firebase project must not block login,
/// device listing, or anything else the app does.
class PushNotificationService {
  PushNotificationService(this._client, {bool? debugMode})
    : _debugMode = debugMode ?? kDebugMode;

  final PushMessagingClient _client;
  final bool _debugMode;

  PushAuthorizationStatus? _authorizationStatus;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefreshSubscription;

  PushAuthorizationStatus? get authorizationStatus => _authorizationStatus;

  /// The current FCM token, but only outside release/profile builds.
  ///
  /// Temporary diagnostic for the Fase 3B.4 manual Firebase Console test.
  /// Remove once Fase 3B.5 registers tokens with the backend for real.
  String? get debugOnlyToken => _debugMode ? _currentToken : null;

  Stream<PushMessage> get onForegroundMessage => _client.onForegroundMessage;

  Stream<PushMessage> get onMessageOpenedApp => _client.onMessageOpenedApp;

  /// Requests permission only when it has not been decided yet, fetches the
  /// initial token, and starts listening for token refreshes. Swallows any
  /// failure so a broken Firebase setup never prevents the rest of the app
  /// from starting.
  Future<void> initialize() async {
    try {
      final status = await _client.getAuthorizationStatus();
      _authorizationStatus = status == PushAuthorizationStatus.notDetermined
          ? await _client.requestPermission()
          : status;
      _currentToken = await _client.getToken();
      _logDebugToken('token inicial');
      _tokenRefreshSubscription = _client.onTokenRefresh.listen((token) {
        _currentToken = token;
        _logDebugToken('token renovado');
      }, onError: (Object _) {});
    } on Object {
      // Sanitized on purpose: never let a raw Firebase/FCM error surface.
    }
  }

  /// The message that opened the app from a fully terminated state, if any.
  Future<PushMessage?> getInitialMessage() async {
    try {
      return await _client.getInitialMessage();
    } on Object {
      return null;
    }
  }

  void _logDebugToken(String label) {
    final token = debugOnlyToken;
    if (token == null) {
      return;
    }
    debugPrint('[FCM][DEBUG-ONLY][interbridge-dev] $label: $token');
  }

  void dispose() {
    unawaited(_tokenRefreshSubscription?.cancel());
  }
}
