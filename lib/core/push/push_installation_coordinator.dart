import '../network/api_failure.dart';
import 'app_version_provider.dart';
import 'installation_id_store.dart';
import 'push_installation_repository.dart';

typedef Delay = Future<void> Function(Duration duration);

class PushInstallationCoordinator {
  PushInstallationCoordinator({
    required this.installationIds,
    required this.appVersions,
    required this.repository,
    Delay? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final InstallationIdStore installationIds;
  final AppVersionProvider appVersions;
  final PushInstallationRepository repository;
  final Delay _delay;
  String? _pendingToken;
  String? _lastRegisteredToken;
  String? _blockedToken;
  bool _authenticated = false;
  bool _running = false;
  bool _startupRepairNeeded = true;
  bool _logoutInProgress = false;
  Future<void>? _work;
  Future<void>? _logoutWork;

  void acceptToken(String token) {
    if (token.isEmpty) return;
    if (_pendingToken != token) _blockedToken = null;
    _pendingToken = token;
    _schedule();
  }

  void setAuthenticated(bool value) {
    final becameAuthenticated = value && !_authenticated;
    _authenticated = value;
    if (!value) {
      _lastRegisteredToken = null;
      _startupRepairNeeded = true;
    } else if (becameAuthenticated) {
      _startupRepairNeeded = true;
      _blockedToken = null;
      _schedule();
    }
  }

  Future<void> get idle => _work ?? Future<void>.value();

  void _schedule() {
    if (!_authenticated ||
        _logoutInProgress ||
        _pendingToken == null ||
        _pendingToken == _blockedToken ||
        _running) {
      return;
    }
    _running = true;
    _work = _drain();
  }

  Future<void> _drain() async {
    try {
      while (_authenticated && !_logoutInProgress && _pendingToken != null) {
        final token = _pendingToken!;
        if (token == _lastRegisteredToken && !_startupRepairNeeded) break;
        final succeeded = await _registerWithRetry(token);
        if (!_authenticated) break;
        if (succeeded) {
          _lastRegisteredToken = token;
          _blockedToken = null;
          _startupRepairNeeded = false;
        } else {
          _blockedToken = token;
        }
        if (_pendingToken == token || !succeeded) break;
      }
    } finally {
      _running = false;
      _work = null;
      if (_authenticated &&
          _pendingToken != null &&
          _pendingToken != _blockedToken &&
          _pendingToken != _lastRegisteredToken) {
        _schedule();
      }
    }
  }

  Future<bool> _registerWithRetry(String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await repository.registerInstallation(
          installationId: await installationIds.getOrCreate(),
          token: token,
          appVersion: await appVersions.load(),
        );
        return true;
      } on ApiFailure catch (failure) {
        if (!_isTemporary(failure.kind) || attempt == 2) return false;
        await _delay(
          failure.retryAfter ?? Duration(milliseconds: 200 * (1 << attempt)),
        );
      } on InstallationIdStoreFailure {
        if (attempt == 2) return false;
        await _delay(Duration(milliseconds: 200 * (1 << attempt)));
      } on Object {
        return false;
      }
    }
    return false;
  }

  static bool _isTemporary(ApiFailureKind kind) => {
    ApiFailureKind.conflict,
    ApiFailureKind.rateLimited,
    ApiFailureKind.server,
    ApiFailureKind.unavailable,
    ApiFailureKind.timeout,
    ApiFailureKind.offline,
  }.contains(kind);

  Future<void> deleteForLogout() {
    return _logoutWork ??= _deleteForLogoutOnce();
  }

  Future<void> _deleteForLogoutOnce() async {
    _logoutInProgress = true;
    try {
      final registrationInProgress = _work;
      if (registrationInProgress != null) {
        await registrationInProgress;
      }
      await repository.deleteInstallation(await installationIds.getOrCreate());
      _lastRegisteredToken = null;
      _startupRepairNeeded = true;
    } on Object {
      _logoutInProgress = false;
      _logoutWork = null;
      _blockedToken = null;
      _schedule();
      rethrow;
    }
  }

  /// Completes the barrier after Cognito has ended the session.
  void completeLogout() {
    _authenticated = false;
    _logoutInProgress = false;
    _logoutWork = null;
    _blockedToken = null;
  }

  /// Repairs the remote record if Cognito sign-out failed after DELETE.
  void restoreAfterLogoutFailure() {
    _authenticated = true;
    _logoutInProgress = false;
    _logoutWork = null;
    _startupRepairNeeded = true;
    _blockedToken = null;
    _schedule();
  }
}
