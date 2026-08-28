import 'dart:async';

import 'package:flutter/foundation.dart';

import 'push_message.dart';
import 'push_messaging_client.dart';

/// App-facing seam for FCM: permission, token, and the foreground/tap/cold-
/// start message paths.
///
/// The UI and other features must go through this service instead of
/// touching `FirebaseMessaging.instance` directly. No failure here is
/// allowed to escape — a broken Firebase project must not block login,
/// device listing, or anything else the app does. [initialize] does network
/// and permission-prompt work, so callers must not await it before the
/// first frame; call it after `runApp` instead.
class PushNotificationService {
  PushNotificationService(
    this._client,
    this._tokenSink, {
    bool? debugMode,
  }) : _debugMode = debugMode ?? kDebugMode;

  final PushMessagingClient _client;
  final bool _debugMode;
  final void Function(String token)? _tokenSink;

  Future<void>? _initialization;

  PushAuthorizationStatus? _authorizationStatus;
  String? _currentToken;
  PushEventDiagnostic? _lastForegroundEvent;
  PushEventDiagnostic? _lastOpenedAppEvent;
  PushEventDiagnostic? _lastInitialMessageEvent;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<PushMessage>? _foregroundSubscription;
  StreamSubscription<PushMessage>? _openedAppSubscription;

  PushAuthorizationStatus? get authorizationStatus => _authorizationStatus;

  /// Whether an FCM token is currently held in memory. Only presence is
  /// exposed — never the value. The token itself stays internal, ready for
  /// Fase 3B.5 to register it with the backend from inside this service.
  bool get hasToken => _currentToken != null;

  PushEventDiagnostic? get lastForegroundEvent => _lastForegroundEvent;
  PushEventDiagnostic? get lastOpenedAppEvent => _lastOpenedAppEvent;
  PushEventDiagnostic? get lastInitialMessageEvent => _lastInitialMessageEvent;

  /// Requests permission only when it has not been decided yet, fetches the
  /// initial token, subscribes once to token refresh/foreground/tap-to-open,
  /// and consults the cold-start initial message once. Idempotent — a
  /// second call returns the same in-flight/completed future instead of
  /// re-running any of this or creating duplicate subscriptions.
  ///
  /// Each phase below is isolated: a failure in one (say, [PushMessagingClient.getToken])
  /// is swallowed and never prevents the others (permission, message
  /// listeners, the cold-start message) from still running. A broken
  /// Firebase setup must never prevent the rest of the app from working.
  Future<void> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    await _initializePermission();
    await _initializeToken();
    _subscribeToMessageStreams();
    await _consumeInitialMessage();
  }

  Future<void> _initializePermission() async {
    try {
      final status = await _client.getAuthorizationStatus();
      _authorizationStatus = status == PushAuthorizationStatus.notDetermined
          ? await _client.requestPermission()
          : status;
    } on Object {
      // Sanitized on purpose: never let a raw Firebase/FCM error surface.
      // Token fetching and message listeners below must still run.
    }
  }

  Future<void> _initializeToken() async {
    try {
      _currentToken = await _client.getToken();
      final token = _currentToken;
      if (token != null) _deliverToken(token);
      _logTokenPresence('token_initial');
    } on Object {
      // Sanitized on purpose. Message listeners below must still run even
      // without a token.
    }
  }

  void _subscribeToMessageStreams() {
    try {
      _tokenRefreshSubscription = _client.onTokenRefresh.listen((token) {
        _currentToken = token;
        _deliverToken(token);
        _logTokenPresence('token_refresh');
      }, onError: (Object _) {});

      _foregroundSubscription = _client.onForegroundMessage.listen((message) {
        _lastForegroundEvent = PushEventDiagnostic.fromMessage(message);
        _logEvent('foreground', _lastForegroundEvent!);
      }, onError: (Object _) {});

      _openedAppSubscription = _client.onMessageOpenedApp.listen((message) {
        _lastOpenedAppEvent = PushEventDiagnostic.fromMessage(message);
        _logEvent('opened_app', _lastOpenedAppEvent!);
      }, onError: (Object _) {});
    } on Object {
      // Sanitized on purpose. The cold-start message check below must
      // still run even if wiring one of these streams failed.
    }
  }

  Future<void> _consumeInitialMessage() async {
    try {
      final initialMessage = await _client.getInitialMessage();
      if (initialMessage != null) {
        _lastInitialMessageEvent = PushEventDiagnostic.fromMessage(
          initialMessage,
        );
        _logEvent('initial_message', _lastInitialMessageEvent!);
      }
    } on Object {
      // Sanitized on purpose. The token and listeners set up above stay
      // active regardless.
    }
  }

  void _deliverToken(String token) {
    try {
      _tokenSink?.call(token);
    } on Object {
      // A registration consumer must never break Firebase message streams.
    }
  }

  /// Logs only whether a token is present — never its value.
  void _logTokenPresence(String label) {
    if (!_debugMode) {
      return;
    }
    debugPrint('[FCM][DEBUG-ONLY] $label present=$hasToken');
  }

  void _logEvent(String path, PushEventDiagnostic diagnostic) {
    if (!_debugMode) {
      return;
    }
    debugPrint(
      '[FCM][DEBUG-ONLY] $path messageId=${diagnostic.messageId ?? '-'} '
      'hasTitle=${diagnostic.hasTitle} hasBody=${diagnostic.hasBody}',
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
  }
}
