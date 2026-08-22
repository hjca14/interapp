import 'dart:async';

import 'package:flutter/foundation.dart';
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

final doorCommandProvider = ChangeNotifierProvider.autoDispose
    .family<DoorCommandActionController, String>((ref, deviceId) {
      final repository = ref.watch(commandRepositoryProvider);
      final controller = CommandController(
        repository: repository,
        tracker: CommandTracker(repository: repository),
        keyGenerator: SecureIdempotencyKeyGenerator(),
      );
      final action = DoorCommandActionController(
        deviceId: deviceId,
        controller: controller,
      );
      ref.listen(authSessionProvider, (_, next) {
        if (next.value?.isSignedIn == false) {
          action.cancel();
        }
      });
      ref.onDispose(action.dispose);
      return action;
    });

class DoorCommandActionController extends ChangeNotifier {
  DoorCommandActionController({
    required String deviceId,
    required CommandController controller,
  }) : _deviceId = DeviceId(deviceId),
       // ignore: prefer_initializing_formals
       _controller = controller;

  final DeviceId _deviceId;
  final CommandController _controller;
  DoorCommandUiState _state = const DoorCommandUiState();
  bool _disposed = false;
  Timer? _cooldownTimer;

  DoorCommandUiState get state => _state;

  Future<void> start() async {
    if (_state.busy || _cooldownTimer?.isActive == true) return;
    _setState(const DoorCommandUiState(phase: DoorCommandPhase.sending));
    try {
      final accepted = await _controller.start(_deviceId);
      if (_disposed) return;
      _setState(const DoorCommandUiState(phase: DoorCommandPhase.waiting));
      await _track(accepted);
    } on ApiFailure catch (error) {
      _handleCreateFailure(error);
    } on CommandTrackingCancelled {
      // Navigation, provider disposal and logout intentionally end silently.
    }
  }

  Future<void> retryCreateAfterTimeout() async {
    if (!_state.canRetryCreate || _state.busy) return;
    _setState(const DoorCommandUiState(phase: DoorCommandPhase.sending));
    try {
      final accepted = await _controller.retryCreateAfterTimeout();
      if (_disposed) return;
      _setState(const DoorCommandUiState(phase: DoorCommandPhase.waiting));
      await _track(accepted);
    } on ApiFailure catch (error) {
      _handleCreateFailure(error);
    } on CommandTrackingCancelled {
      // See start(): cancellation is a lifecycle event, not user-facing error.
    }
  }

  Future<void> _track(AcceptedCommand accepted) async {
    try {
      final result = await _controller.track(accepted);
      if (_disposed) return;
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
      _setState(
        DoorCommandUiState(
          phase: DoorCommandPhase.failed,
          message: error.message,
        ),
      );
    }
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
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(retryAfter, () {
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

  void cancel() => _controller.cancelTracking();

  void _setState(DoorCommandUiState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldownTimer?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }
}
