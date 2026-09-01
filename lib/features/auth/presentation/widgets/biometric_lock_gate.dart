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
///
/// The same exception extends to the lock *decision* itself, not only the
/// prompt: [didChangeAppLifecycleState] never treats an inactive/paused/
/// resumed cycle caused by a call's own presentation (notification shade, a
/// tap, full-screen intent, `MainActivity` toggling `showWhenLocked`, the
/// system prompt over it, returning from the call screen) as the user
/// backgrounding the app. This is not simply "is a call in flight right now
/// at `resumed`" — on real Android, `endCall()` (Atender, Dispensar,
/// `RING_ENDED`, the local ring-timeout) can just as easily land *before*
/// the matching `resumed` as after it, and by then [_callInFlight] has
/// already gone back to `false`. [_backgroundCycleIsCallAssociated] is the
/// latch that closes that race: it records, for the *background cycle
/// currently in progress* (see [_backgroundedAt]), whether a call was ever
/// in flight at any point during it — set the instant the cycle begins if a
/// call is already in flight, or the instant one starts mid-cycle (see
/// [_onRingCallChanged]) — and deliberately never cleared just because the
/// call later ends before the cycle's own `resumed` arrives. See that
/// field's and [didChangeAppLifecycleState]'s doc for the precise, bounded,
/// scoped-per-cycle rule: never a permanent bypass, and never grants access
/// to an app that was already locked before the call.
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

  /// Whether the background cycle currently open (i.e. while
  /// [_backgroundedAt] is non-null) has, at any point since it began, had a
  /// call pending/active — see the class doc and
  /// [didChangeAppLifecycleState]'s doc for exactly how this closes the
  /// end-before-resume race. Only ever:
  ///  - set to `true` (never explicitly reset to `false` mid-cycle — once a
  ///    call has touched this cycle, ending it does not un-mark it);
  ///  - read and reset together, exactly once, when the matching `resumed`
  ///    consumes it (or the state is torn down — see [dispose]);
  ///  - reset when a *new* cycle begins ([_backgroundedAt] transitioning
  ///    from `null`), so it never carries meaning across two different
  ///    cycles;
  ///  - reset when the tracked coordinator itself is replaced (see
  ///    [didChangeDependencies]) — a latch about a call is meaningless once
  ///    that call's own coordinator is gone.
  bool _backgroundCycleIsCallAssociated = false;

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
      // A latch referring to a call tracked by the previous coordinator
      // instance carries no meaning under a new one (e.g. across a
      // provider/session reset) — never let it survive the swap.
      _backgroundCycleIsCallAssociated = false;
    }
  }

  void _onRingCallChanged() {
    if (_backgroundedAt != null && _callInFlight) {
      // A call became pending/active partway through the background cycle
      // already in progress (e.g. the notification shade opened first, and
      // only the subsequent tap accepted the call) — mark this cycle
      // call-associated from this point on, same as if it had already been
      // in flight when the cycle began.
      _backgroundCycleIsCallAssociated = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ringCoordinator?.removeListener(_onRingCallChanged);
    WidgetsBinding.instance.removeObserver(this);
    _backgroundedAt = null;
    _backgroundCycleIsCallAssociated = false;
    super.dispose();
  }

  /// A generous cap — far beyond any plausible full-screen-intent
  /// transition, authorization lookup, or Atender/Dispensar interaction,
  /// but far short of a real "the user put the phone down" absence — on how
  /// stale a call-associated background cycle (see
  /// [_backgroundCycleIsCallAssociated]) may be before its own `resumed`
  /// still honors it. Deliberately combined with that explicit latch, never
  /// used on its own: this is what stops an old, already-ended call from
  /// suppressing a lock indefinitely if the user then genuinely stayed away
  /// long past the call itself, and is not a substitute for the latch — a
  /// currently in-flight call ([_callInFlight] below) is never subject to
  /// this cap at all.
  static const _maxCallAssociatedBackgroundDuration = Duration(minutes: 2);

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
      if (_backgroundedAt == null) {
        // The start of a new cycle: never inherit a stale association from
        // whatever the previous cycle was classified as.
        _backgroundedAt = _now;
        _backgroundCycleIsCallAssociated = _callInFlight;
      }
      return;
    }
    if (state != AppLifecycleState.resumed || _backgroundedAt == null) {
      return;
    }
    final elapsed = _now.difference(_backgroundedAt!);
    final callAssociated = _backgroundCycleIsCallAssociated;
    _backgroundedAt = null;
    _backgroundCycleIsCallAssociated = false;
    if (_callInFlight) {
      // A call is still pending/active right this moment — never locks
      // regardless of elapsed time; see the class doc and [build]'s own
      // unconditional exception while a call is in flight.
      return;
    }
    if (callAssociated && elapsed <= _maxCallAssociatedBackgroundDuration) {
      // This cycle's inactive/paused/resumed was caused by a call's own
      // presentation, even though that call already ended (Atender,
      // Dispensar, RING_ENDED, the local ring-timeout) *before* this
      // resumed arrived — the exact race a same-instant _callInFlight check
      // alone cannot close, since by then it has already gone back to
      // false. Elapsed time is discarded rather than evaluated, same as
      // when the call is still in flight.
      //
      // This is not a persistent bypass: it only ever *skips newly
      // locking* for this one resume — an already-[_locked] app (cold
      // start, over the keyguard, or locked before the call arrived) stays
      // exactly as locked as it was, since nothing here ever sets `_locked
      // = false`. The next resume that is not itself call-associated is
      // evaluated normally, with a fresh cycle and no memory of this one.
      return;
    }
    final settings = ref.read(biometricLockSettingsProvider).value;
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
