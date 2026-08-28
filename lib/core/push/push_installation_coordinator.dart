import '../network/api_failure.dart';
import 'app_version_provider.dart';
import 'installation_id_store.dart';
import 'push_installation_repository.dart';

typedef Delay = Future<void> Function(Duration duration);

class PushInstallationCoordinator {
  PushInstallationCoordinator({
    required InstallationIdStore installationIds,
    required AppVersionProvider appVersions,
    required PushInstallationRepository repository,
    Delay? delay,
  }) : _installationIds = installationIds,
       _appVersions = appVersions,
       _repository = repository,
       _delay = delay ?? Future<void>.delayed;

  final InstallationIdStore _installationIds;
  final AppVersionProvider _appVersions;
  final PushInstallationRepository _repository;
  final Delay _delay;
  String? _pendingToken;
  String? _lastRegisteredToken;
  String? _blockedToken;
  bool _authenticated = false;
  bool _running = false;
  bool _startupRepairNeeded = true;
  Future<void>? _work;

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
      while (_authenticated && _pendingToken != null) {
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
        await _repository.registerInstallation(
          installationId: await _installationIds.getOrCreate(),
          token: token,
          appVersion: await _appVersions.load(),
        );
        return true;
      } on ApiFailure catch (failure) {
        if (!_isTemporary(failure.kind) || attempt == 2) return false;
        await _delay(
          failure.retryAfter ?? Duration(milliseconds: 200 * (1 << attempt)),
        );
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

  Future<void> deleteForLogout() async {
    await _repository.deleteInstallation(await _installationIds.getOrCreate());
    _lastRegisteredToken = null;
    _startupRepairNeeded = true;
  }

  /// Repairs the remote record if Cognito sign-out failed after DELETE.
  void requestAuthenticatedRepair() {
    _startupRepairNeeded = true;
    _blockedToken = null;
    _schedule();
  }
}
