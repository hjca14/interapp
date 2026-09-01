import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/ring_call_navigation.dart';
import '../../../devices/presentation/providers/devices_providers.dart';
import '../../domain/services/biometric_lock.dart';
import '../providers/auth_providers.dart';
import '../providers/biometric_lock_providers.dart';

/// Classifies the background cycle currently open in
/// [_BiometricLockGateState._cycleClassification], distinguishing a call's
/// own presentation (which must not disturb an already-unlocked app) from a
/// genuine departure (which must apply the configured lock policy normally,
/// even if a call happens to arrive — and end — while the user was away).
enum _BackgroundCycleClassification {
  /// No background cycle is open (initial value, and the value the field
  /// is reset to whenever a cycle is consumed or torn down).
  none,

  /// A cycle that began with `inactive` from an app that was foreground and
  /// unlocked, with no call in flight yet and no `paused`/`hidden` evidence
  /// yet. Still ambiguous: `inactive` alone is emitted for many transient
  /// reasons (notification shade, dialogs, a call arriving) that do not by
  /// themselves prove the user left. Resolves one of two ways:
  ///  - a call becomes pending/active during this window →
  ///    [callPresentationFromForeground] (see [_onRingCallChanged]);
  ///  - `paused`/`hidden` arrives with no call ever having touched it →
  ///    [genuineBackground] (see [didChangeAppLifecycleState]).
  foregroundTransientCandidate,

  /// This cycle is, or became, attributable to a call's own presentation
  /// (notification shade, a tap, full-screen intent, `MainActivity`
  /// toggling `showWhenLocked`, the system prompt over it, returning from
  /// the call screen) from an app that was foreground and unlocked *before*
  /// the call ever touched it — whether the call was already in flight the
  /// instant the cycle began, or arrived mid-cycle while still a
  /// [foregroundTransientCandidate]. The matching `resumed` must not lock,
  /// regardless of whether the call has since ended (see
  /// [_maxCallAssociatedBackgroundDuration] for the only exception: an
  /// implausibly stale cycle, treated as a safeguard against impossible
  /// state, never as the primary decision).
  callPresentationFromForeground,

  /// This cycle is definitively a real departure — the app was already
  /// locked when it began, or `paused`/`hidden` was observed with no call
  /// ever having touched it first. Once a cycle reaches this value it is
  /// permanent for the rest of the cycle: a call arriving afterward (or
  /// still being active, or even ending) never reclassifies it back to
  /// [callPresentationFromForeground] — see [_onRingCallChanged], which
  /// only ever upgrades from [foregroundTransientCandidate]. The matching
  /// `resumed` applies the configured lock policy normally.
  genuineBackground,
}

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
/// prompt — but only for a background cycle actually **caused by** a call's
/// own presentation (notification shade, a tap, full-screen intent,
/// `MainActivity` toggling `showWhenLocked`, the system prompt over it,
/// returning from the call screen) from an app that was already foreground
/// and unlocked. A cycle that began with the user genuinely leaving —
/// `paused`/`hidden` observed before any call ever touched it — must apply
/// the configured lock policy normally, *even if* a call happens to arrive,
/// and even end, while the user was away: that is not the same event this
/// exception exists for, and conflating the two would let an unrelated
/// incoming call quietly disable the lock for a real departure.
///
/// [_BackgroundCycleClassification] (see [_cycleClassification]) is the
/// state machine that tells these apart. It is not simply "is a call in
/// flight right now at `resumed`": on real Android, `endCall()` (Atender,
/// Dispensar, `RING_ENDED`, the local ring-timeout) can just as easily land
/// *before* the matching `resumed` as after it, and by then [_callInFlight]
/// has already gone back to `false` — a same-instant check alone cannot
/// distinguish that from the call never having been in flight at all during
/// this cycle. See [_BackgroundCycleClassification]'s and
/// [didChangeAppLifecycleState]'s doc for the full transition rules: never a
/// permanent bypass, and never grants access to an app that was already
/// locked before the call.
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

  /// Classification of the background cycle currently open (while
  /// [_backgroundedAt] is non-null) — see [_BackgroundCycleClassification]
  /// for what each value means. Only ever:
  ///  - assigned by [didChangeAppLifecycleState] (cycle start, and a
  ///    `paused`/`hidden` ruling out the call-presentation exception) and by
  ///    [_onRingCallChanged] (a call touching an open, still-ambiguous
  ///    cycle);
  ///  - read and reset together, exactly once, when the matching `resumed`
  ///    consumes it (or the state is torn down — see [dispose]);
  ///  - reset to [_BackgroundCycleClassification.none] when a *new* cycle
  ///    begins, so it never carries meaning across two different cycles;
  ///  - reset when the tracked coordinator itself is replaced (see
  ///    [_bindCoordinator]) — a classification referring to a call is
  ///    meaningless once that call's own coordinator is gone.
  _BackgroundCycleClassification _cycleClassification =
      _BackgroundCycleClassification.none;

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
    _bindCoordinator(ref.read(ringCallNavigationCoordinatorProvider));
  }

  /// Starts tracking [coordinator] for [_callInFlight]/[_onRingCallChanged],
  /// detaching from whatever coordinator was tracked before. Called once
  /// from [initState] for the coordinator this gate mounts with, and again
  /// from [build]'s `ref.listen` below whenever the provider is overridden
  /// with a *different* instance afterward (e.g. a session/provider reset)
  /// — `didChangeDependencies` is not a reliable signal for that live swap,
  /// since this widget never `ref.watch`es the coordinator provider itself.
  void _bindCoordinator(RingCallNavigationCoordinator coordinator) {
    if (identical(_ringCoordinator, coordinator)) return;
    _ringCoordinator?.removeListener(_onRingCallChanged);
    _ringCoordinator = coordinator..addListener(_onRingCallChanged);
    // A classification referring to a call tracked by the previous
    // coordinator instance carries no meaning under a new one — never let
    // it survive the swap. The cycle's own start time (if one is open) is
    // deliberately left untouched: only what it was caused by is now
    // unknown again, not whether one is open at all — the matching resumed
    // still evaluates the configured policy normally against it.
    _cycleClassification = _BackgroundCycleClassification.none;
  }

  void _onRingCallChanged() {
    if (_backgroundedAt != null &&
        _cycleClassification ==
            _BackgroundCycleClassification.foregroundTransientCandidate &&
        _callInFlight) {
      // A call became pending/active partway through a still-ambiguous
      // cycle (e.g. the notification shade opened first, and only the
      // subsequent tap accepted the call) — now unambiguously the call's
      // own presentation. A cycle already ruled [genuineBackground] is
      // deliberately left untouched here — see that value's doc: once the
      // user has genuinely left, a call arriving afterward must never
      // reclassify it back.
      _cycleClassification =
          _BackgroundCycleClassification.callPresentationFromForeground;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ringCoordinator?.removeListener(_onRingCallChanged);
    WidgetsBinding.instance.removeObserver(this);
    _backgroundedAt = null;
    _cycleClassification = _BackgroundCycleClassification.none;
    super.dispose();
  }

  /// A defensive safeguard only — never the primary decision. The state
  /// machine in [_BackgroundCycleClassification] is what actually tells a
  /// call's own presentation apart from a genuine departure; this cap just
  /// stops an implausibly stale
  /// [_BackgroundCycleClassification.callPresentationFromForeground]
  /// classification (impossible in normal operation, but not something to
  /// trust indefinitely) from suppressing a lock forever. Far beyond any
  /// plausible full-screen-intent transition, authorization lookup, or
  /// Atender/Dispensar interaction, but far short of a real "the user put
  /// the phone down" absence.
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
        // The start of a new cycle: never inherit a stale classification
        // from whatever the previous cycle ended up as.
        _backgroundedAt = _now;
        _cycleClassification = switch (true) {
          _ when _locked =>
            // Not "foreground and unlocked" to begin with — this cycle is
            // never eligible for the call-presentation exception at all,
            // regardless of any call that arrives during it; see the class
            // doc's "app already locked" guarantee.
            _BackgroundCycleClassification.genuineBackground,
          _ when _callInFlight =>
            // Rule: already in flight the instant an unlocked foreground
            // cycle begins — unambiguously the call's own presentation.
            _BackgroundCycleClassification.callPresentationFromForeground,
          _ when state == AppLifecycleState.inactive =>
            // `inactive` alone does not yet prove the user left — still
            // ambiguous until `paused`/`hidden` or a call resolves it.
            _BackgroundCycleClassification.foregroundTransientCandidate,
          _ =>
            // `paused`/`hidden` arriving directly, with no prior `inactive`
            // in this cycle and no call yet — already strong enough
            // evidence of a real departure on its own.
            _BackgroundCycleClassification.genuineBackground,
        };
      } else if (state != AppLifecycleState.inactive &&
          _cycleClassification ==
              _BackgroundCycleClassification.foregroundTransientCandidate) {
        // paused/hidden arriving mid-cycle, before any call ever touched
        // it, definitively rules out the call-presentation exception for
        // the rest of this cycle — see [_BackgroundCycleClassification
        // .genuineBackground]'s doc: permanent, never reclassified back.
        _cycleClassification = _BackgroundCycleClassification.genuineBackground;
      }
      return;
    }
    if (state != AppLifecycleState.resumed || _backgroundedAt == null) {
      return;
    }
    final elapsed = _now.difference(_backgroundedAt!);
    final classification = _cycleClassification;
    _backgroundedAt = null;
    _cycleClassification = _BackgroundCycleClassification.none;
    if (classification ==
            _BackgroundCycleClassification.callPresentationFromForeground &&
        elapsed <= _maxCallAssociatedBackgroundDuration) {
      // This cycle's inactive/paused/resumed was caused by a call's own
      // presentation from an app that was already foreground and unlocked
      // — even if that call already ended (Atender, Dispensar, RING_ENDED,
      // the local ring-timeout) *before* this resumed arrived. Elapsed time
      // is discarded rather than evaluated.
      //
      // This is not a persistent bypass: it only ever *skips newly
      // locking* for this one resume — an already-[_locked] app can never
      // reach this classification in the first place (see the cycle-start
      // switch above), so it stays exactly as locked as it was, since
      // nothing here ever sets `_locked = false`. The next resume that is
      // not itself classified this way is evaluated normally, with a fresh
      // cycle and no memory of this one.
      return;
    }
    // Every other classification — [genuineBackground] (the user actually
    // left, whether or not a call happened to arrive and even end while
    // they were away) or [foregroundTransientCandidate]/[none] (no call
    // ever touched this cycle, so there is nothing to except) — applies the
    // configured policy normally. This deliberately runs even while
    // [_callInFlight] is still true right now (the user stepped away, and a
    // call happens to be active when they return): [_locked] is set here
    // regardless, but [build]'s own unconditional exception keeps the lock
    // screen itself hidden behind the call until it ends, at which point
    // the next rebuild reveals it — satisfying "pode apresentar a chamada,
    // mas depois do término o conteúdo protegido continua exigindo
    // autenticação" without a separate deferred-evaluation mechanism.
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
    // The reliable trigger for a live coordinator swap — see
    // [_bindCoordinator]'s doc.
    ref.listen<RingCallNavigationCoordinator>(
      ringCallNavigationCoordinatorProvider,
      (previous, next) {
        _bindCoordinator(next);
        if (mounted) setState(() {});
      },
    );
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
    if (!enabled) {
      // Disabling the lock invalidates any in-progress background-cycle
      // classification — see [_BackgroundCycleClassification]'s doc. If the
      // user re-enables it later, the next cycle must be judged fresh, not
      // by whatever a call happened to be doing while protection was off.
      _backgroundedAt = null;
      _cycleClassification = _BackgroundCycleClassification.none;
    }
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
