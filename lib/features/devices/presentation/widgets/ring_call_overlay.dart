import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/ring_call_navigation.dart';
import '../pages/incoming_call_page.dart';
import '../providers/devices_providers.dart';

/// Sits on top of whatever `MaterialApp.router` is currently showing —
/// wired via `InterApp`'s `builder`, not a route — so a call never navigates
/// away from (and therefore never loses) the screen/stack the user was
/// already on. This is what fixes three related problems the old
/// `/incoming-call` redirect route had:
///
/// - a redirect briefly rendered whatever `initialLocation` resolved to
///   (typically the lock-guarded `HomePage`) interactively, before the
///   coordinator's async device-authorization lookup finished — an overlay
///   instead sits in front of that from the very first frame the call is
///   known about (see [RingCallNavigationCoordinator.isValidating]);
/// - dismissing always redirected back to `/`, discarding whatever route
///   was open before the call — an overlay never touches the route stack at
///   all, so whatever was there is simply revealed again;
/// - `HomePage`'s `BiometricLockGate` only lives on the `/` route: routing
///   away to `/incoming-call` and back could force a fresh instance of it to
///   re-lock. An overlay never rebuilds `HomePage`, so it never does.
class RingCallOverlay extends ConsumerWidget {
  const RingCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(ringCallNavigationCoordinatorProvider);
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final active = coordinator.active;
        if (active != null) {
          return Positioned.fill(
            child: Material(
              child: IncomingCallPage(
                intent: active,
                onDismiss: coordinator.consumed,
              ),
            ),
          );
        }
        if (coordinator.isValidating) {
          return const _ValidatingSurface();
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Opaque and non-interactive on purpose: whatever screen is underneath
/// (commonly the lock-guarded `HomePage`) must be neither visible nor
/// tappable while a tapped/launched call is still being authorized.
class _ValidatingSurface extends StatelessWidget {
  const _ValidatingSurface();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: IgnorePointer(
          ignoring: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Validando chamada…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
