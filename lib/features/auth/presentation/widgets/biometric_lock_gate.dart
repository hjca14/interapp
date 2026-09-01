import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/ring_call_navigation.dart';
import '../../../devices/presentation/providers/devices_providers.dart';
import '../../domain/services/biometric_lock.dart';
import '../providers/auth_providers.dart';
import '../providers/biometric_lock_providers.dart';

/// Covers authenticated content after the configured background timeout.
///
/// This gate does not wrap registration, confirmation, or recovery routes.
/// It can only unlock after [BiometricUnlockService] verifies that Cognito is
/// still signed in, and always offers normal login as a fallback.
///
/// An incoming call is a deliberate exception to this gate: while
/// `RingCallNavigationCoordinator` has a call pending or active, this widget
/// renders [child] unconditionally, never scheduling (or showing) an
/// automatic biometric prompt — see [_callInFlight]. `RingCallOverlay` sits
/// visually on top of whatever this gate renders, but a *native* OS
/// biometric prompt would still render above that Flutter-level overlay if
/// this gate started one underneath; the point of this exception is to
/// never start one while a call is in flight in the first place, not to
/// rely on being visually covered.
class BiometricLockGate extends ConsumerStatefulWidget {
  const BiometricLockGate({super.key, required this.child, this.now});

  final Widget child;
  final DateTime Function()? now;

  @override
  ConsumerState<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends ConsumerState<BiometricLockGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _locked = false;
  bool _initialSettingsHandled = false;
  bool _unlocking = false;
  bool _automaticAttemptScheduled = false;
  String? _message;
  RingCallNavigationCoordinator? _ringCoordinator;

  DateTime get _now => (widget.now ?? DateTime.now)();

  bool get _callInFlight =>
      _ringCoordinator != null &&
      (_ringCoordinator!.hasPending || _ringCoordinator!.shouldOpen);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = ref.read(ringCallNavigationCoordinatorProvider);
    if (!identical(_ringCoordinator, coordinator)) {
      _ringCoordinator?.removeListener(_onRingCallChanged);
      _ringCoordinator = coordinator..addListener(_onRingCallChanged);
    }
  }

  void _onRingCallChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ringCoordinator?.removeListener(_onRingCallChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The native biometric sheet can itself emit inactive/resumed events.
    // Ignoring those events prevents its dismissal from scheduling a new sheet.
    if (_unlocking) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= _now;
      return;
    }
    if (state != AppLifecycleState.resumed || _backgroundedAt == null) {
      return;
    }
    final settings = ref.read(biometricLockSettingsProvider).value;
    final elapsed = _now.difference(_backgroundedAt!);
    _backgroundedAt = null;
    if (settings != null && shouldLockAfterBackground(settings, elapsed)) {
      setState(() {
        _locked = true;
        _message = null;
        _automaticAttemptScheduled = false;
      });
      _scheduleAutomaticUnlock();
    }
  }

  void _scheduleAutomaticUnlock() {
    // Never start a native biometric prompt while a call is pending/active
    // — see the class doc comment. Deliberately checked here (not just
    // inside the deferred callback) and without setting
    // [_automaticAttemptScheduled]: once the call ends, the next rebuild
    // this triggers (`_onRingCallChanged`) calls this again with a clean
    // slate, so the normal automatic attempt still happens exactly once,
    // just deferred past the call instead of skipped.
    if (_automaticAttemptScheduled || _callInFlight) return;
    _automaticAttemptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _locked) _unlock();
    });
  }

  Future<void> _unlock() async {
    if (_unlocking) {
      return;
    }
    setState(() {
      _unlocking = true;
      _message = null;
    });
    final result = await ref.read(biometricUnlockServiceProvider).unlock();
    if (!mounted) {
      return;
    }
    setState(() {
      _unlocking = false;
      if (result == BiometricAuthenticationResult.success) {
        _locked = false;
      } else {
        _message = biometricResultMessage(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(biometricLockSettingsProvider);
    if (settings.isLoading && !settings.hasValue) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!settings.hasValue) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Center(
          child: Text(
            'Não foi possível carregar as preferências de segurança.',
          ),
        ),
      );
    }
    final enabled = settings.requireValue.enabled;
    if (!_initialSettingsHandled) {
      _initialSettingsHandled = true;
      _locked = enabled;
    }
    if (!enabled || !_locked || _callInFlight) {
      return widget.child;
    }
    _scheduleAutomaticUnlock();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  48,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fingerprint, size: 72),
                    const SizedBox(height: 16),
                    Text(
                      'Desbloqueie para continuar',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Confirme sua biometria para acessar o InterBridge.',
                      textAlign: TextAlign.center,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _unlocking ? null : _unlock,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(
                        _unlocking ? 'Verificando...' : 'Desbloquear',
                      ),
                    ),
                    TextButton(
                      onPressed: _unlocking
                          ? null
                          : () => ref.read(authRepositoryProvider).signOut(),
                      child: const Text('Entrar com e-mail e senha'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
