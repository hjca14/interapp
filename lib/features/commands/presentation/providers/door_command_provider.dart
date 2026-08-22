import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/network/api_failure.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../devices/presentation/providers/devices_providers.dart';
import '../../data/command_repository.dart';
import '../../domain/command_controller.dart';
import '../../domain/command_models.dart';
import '../../domain/command_tracker.dart';
import '../../domain/idempotency.dart';

enum DoorCommandPhase {
  idle,
  sending,
  waiting,
  completed,
  rejected,
  timedOut,
  failed,
  cancelled,
}

abstract interface class DoorCommandCooldown {
  void cancel();
}

abstract interface class DoorCommandCooldownScheduler {
  DoorCommandCooldown schedule(Duration duration, VoidCallback callback);
}

final class TimerDoorCommandCooldownScheduler
    implements DoorCommandCooldownScheduler {
  const TimerDoorCommandCooldownScheduler();

  @override
  DoorCommandCooldown schedule(Duration duration, VoidCallback callback) {
    return _TimerDoorCommandCooldown(Timer(duration, callback));
  }
}

final class _TimerDoorCommandCooldown implements DoorCommandCooldown {
  _TimerDoorCommandCooldown(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

@immutable
class DoorCommandUiState {
  const DoorCommandUiState({
    this.phase = DoorCommandPhase.idle,
    this.message,
    this.canRetryCreate = false,
    this.retryAfter,
  });

  final DoorCommandPhase phase;
  final String? message;
  final bool canRetryCreate;
  final Duration? retryAfter;

  bool get busy =>
      phase == DoorCommandPhase.sending || phase == DoorCommandPhase.waiting;
}

final commandRepositoryProvider = Provider<CommandRepository>((ref) {
  return HttpCommandRepository(ref.watch(apiClientProvider));
});

final doorCommandCooldownSchedulerProvider =
    Provider<DoorCommandCooldownScheduler>(
      (_) => const TimerDoorCommandCooldownScheduler(),
    );

final doorCommandProvider = ChangeNotifierProvider.autoDispose
    .family<DoorCommandActionController, String>((ref, deviceId) {
      final repository = ref.watch(commandRepositoryProvider);
      CommandController createController() => CommandController(
        repository: repository,
        tracker: CommandTracker(repository: repository),
        keyGenerator: SecureIdempotencyKeyGenerator(),
      );
      final action = DoorCommandActionController(
        deviceId: deviceId,
        controller: createController(),
        controllerFactory: createController,
        cooldownScheduler: ref.watch(doorCommandCooldownSchedulerProvider),
      );
      final lifecycle = _DoorCommandLifecycleObserver(action);
      ref.listen(authSessionProvider, (_, next) {
        if (next.value?.isSignedIn == false) {
          action.cancelForLogout();
        }
      });
      ref.onDispose(() {
        lifecycle.dispose();
        action.dispose();
      });
      return action;
    });

final class _DoorCommandLifecycleObserver with WidgetsBindingObserver {
  _DoorCommandLifecycleObserver(this._action) {
    WidgetsBinding.instance.addObserver(this);
  }

  final DoorCommandActionController _action;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _action.cancelForLifecycle();
    } else if (state == AppLifecycleState.resumed) {
      _action.resumeAfterLifecycle();
    }
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}

class DoorCommandActionController extends ChangeNotifier {
  DoorCommandActionController({
    required String deviceId,
    required CommandController controller,
    CommandController Function()? controllerFactory,
    DoorCommandCooldownScheduler cooldownScheduler =
        const TimerDoorCommandCooldownScheduler(),
  }) : _deviceId = DeviceId(deviceId),
       // ignore: prefer_initializing_formals
       _controller = controller,
       // ignore: prefer_initializing_formals
       _controllerFactory = controllerFactory,
       // ignore: prefer_initializing_formals
       _cooldownScheduler = cooldownScheduler;

  final DeviceId _deviceId;
  CommandController _controller;
  final CommandController Function()? _controllerFactory;
  final DoorCommandCooldownScheduler _cooldownScheduler;
  DoorCommandUiState _state = const DoorCommandUiState();
  bool _disposed = false;
  DoorCommandCooldown? _cooldown;
  bool _cooldownActive = false;
  bool _cancelled = false;
  bool _lifecycleCancelled = false;
  int _controllerGeneration = 0;

  DoorCommandUiState get state => _state;

  Future<void> start() async {
    if (_state.busy || _cooldownActive || _cancelled) return;
    final operationController = _controller;
    final operationGeneration = _controllerGeneration;
    _setState(const DoorCommandUiState(phase: DoorCommandPhase.sending));
    try {
      final accepted = await operationController.start(_deviceId);
      if (!_isCurrentOperation(operationController, operationGeneration)) {
        return;
      }
      _setState(const DoorCommandUiState(phase: DoorCommandPhase.waiting));
      await _track(accepted, operationController, operationGeneration);
    } on ApiFailure catch (error) {
      if (_isCurrentOperation(operationController, operationGeneration)) {
        _handleCreateFailure(error);
      }
    } on CommandTrackingCancelled {
      // Navigation, provider disposal and logout intentionally end silently.
    }
  }

  Future<void> retryCreateAfterTimeout() async {
    if (!_state.canRetryCreate ||
        _state.busy ||
        _cooldownActive ||
        _cancelled) {
      return;
    }
    final operationController = _controller;
    final operationGeneration = _controllerGeneration;
    _setState(const DoorCommandUiState(phase: DoorCommandPhase.sending));
    try {
      final accepted = await operationController.retryCreateAfterTimeout();
      if (!_isCurrentOperation(operationController, operationGeneration)) {
        return;
      }
      _setState(const DoorCommandUiState(phase: DoorCommandPhase.waiting));
      await _track(accepted, operationController, operationGeneration);
    } on ApiFailure catch (error) {
      if (_isCurrentOperation(operationController, operationGeneration)) {
        _handleCreateFailure(error);
      }
    } on CommandTrackingCancelled {
      // See start(): cancellation is a lifecycle event, not user-facing error.
    }
  }

  Future<void> _track(
    AcceptedCommand accepted,
    CommandController operationController,
    int operationGeneration,
  ) async {
    try {
      final result = await operationController.track(accepted);
      if (!_isCurrentOperation(operationController, operationGeneration)) {
        return;
      }
      if (result == null || result.state == CommandState.expired) {
        _setState(
          const DoorCommandUiState(
            phase: DoorCommandPhase.timedOut,
            message: 'O dispositivo não confirmou a solicitação a tempo.',
          ),
        );
      } else if (result.state == CommandState.completed) {
        _setState(
          const DoorCommandUiState(
            phase: DoorCommandPhase.completed,
            message: 'Abertura confirmada pelo dispositivo.',
          ),
        );
      } else if (result.state == CommandState.rejected) {
        final capabilityDisabled =
            result.rejection?.code == 'CAPABILITY_DISABLED';
        _setState(
          DoorCommandUiState(
            phase: DoorCommandPhase.rejected,
            message: capabilityDisabled
                ? 'A abertura ainda não está configurada neste dispositivo.\nNenhuma ação física foi realizada.'
                : 'O dispositivo recusou a solicitação.',
          ),
        );
      }
    } on ApiFailure catch (error) {
      if (_isCurrentOperation(operationController, operationGeneration)) {
        _setState(
          DoorCommandUiState(
            phase: DoorCommandPhase.failed,
            message: error.message,
          ),
        );
      }
    }
  }

  bool _isCurrentOperation(
    CommandController operationController,
    int operationGeneration,
  ) {
    return !_disposed &&
        !_cancelled &&
        identical(operationController, _controller) &&
        operationGeneration == _controllerGeneration;
  }

  void _handleCreateFailure(ApiFailure error) {
    if (_disposed) return;
    final ambiguousTimeout = error.kind == ApiFailureKind.timeout;
    _setState(
      DoorCommandUiState(
        phase: ambiguousTimeout
            ? DoorCommandPhase.timedOut
            : DoorCommandPhase.failed,
        message: ambiguousTimeout
            ? 'Não foi possível confirmar se a solicitação foi recebida.'
            : error.message,
        canRetryCreate: ambiguousTimeout,
        retryAfter: error.retryAfter,
      ),
    );
    final retryAfter = error.retryAfter;
    if (retryAfter != null && retryAfter > Duration.zero) {
      _cooldown?.cancel();
      _cooldownActive = true;
      _cooldown = _cooldownScheduler.schedule(retryAfter, () {
        _cooldownActive = false;
        _cooldown = null;
        _setState(
          DoorCommandUiState(
            phase: _state.phase,
            message: _state.message,
            canRetryCreate: _state.canRetryCreate,
          ),
        );
      });
    }
  }

  void cancelForLifecycle() {
    if (!_state.busy || _cancelled) return;
    _lifecycleCancelled = true;
    _cancelAttempt();
  }

  void resumeAfterLifecycle() {
    if (_disposed || !_lifecycleCancelled) return;
    final createController = _controllerFactory;
    if (createController == null) return;
    _lifecycleCancelled = false;
    final cancelledController = _controller;
    _controllerGeneration++;
    _controller = createController();
    _cancelled = false;
    unawaited(cancelledController.dispose());
    _setState(const DoorCommandUiState());
  }

  void cancelForLogout() {
    _lifecycleCancelled = false;
    if (_state.busy) {
      _cancelAttempt();
    } else {
      _cancelled = true;
    }
  }

  void cancel() => _cancelAttempt();

  void _cancelAttempt() {
    if (!_state.busy || _cancelled) return;
    _cancelled = true;
    _cooldownActive = false;
    _cooldown?.cancel();
    _cooldown = null;
    _controller.cancelTracking();
    _setState(
      const DoorCommandUiState(
        phase: DoorCommandPhase.cancelled,
        message: 'Solicitação interrompida.',
      ),
    );
  }

  void _setState(DoorCommandUiState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldown?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }
}
