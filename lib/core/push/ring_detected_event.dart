/// How a validated `RING_DETECTED` push should be presented locally.
///
/// Mirrors the backend's `presentation_intent` wire values exactly — see
/// [ring_detected_push_parser.dart]'s `_parsePresentationIntent`.
///
/// [ringAndNotification] is a **legacy** value: the notification-preferences
/// contract and this app's UI now write only [ringOnly]/[notificationOnly]/
/// `NONE` (see `AlertMode`), but the backend may still emit
/// `RING_AND_NOTIFICATION` for an account that has not been touched since
/// before that migration, or during the backend's own rollout. Every call
/// site that branches on "is this a call" must treat [ringAndNotification]
/// identically to [ringOnly] (see [RingPresentationIntent.isCall]) — it must
/// never be written by this app again, but reading it must never break.
enum RingPresentationIntent { ringOnly, notificationOnly, ringAndNotification }

extension RingPresentationIntentCall on RingPresentationIntent {
  /// Whether this intent should present the call experience (full-screen,
  /// continuous ringtone, `IncomingCallPage`) rather than a plain
  /// notification. True for [RingPresentationIntent.ringOnly] and the
  /// legacy [RingPresentationIntent.ringAndNotification].
  bool get isCall =>
      this == RingPresentationIntent.ringOnly ||
      this == RingPresentationIntent.ringAndNotification;
}

/// Common identity shared by both `RING_DETECTED` and `RING_ENDED` — see
/// [RingDetectedEvent] and [RingEndedEvent]. Sealed so
/// `ring_detected_push_parser.dart`/`ring_detected_presenter.dart` can
/// exhaustively `switch` on which one a push turned out to be.
sealed class RingPushEvent {
  const RingPushEvent({
    required this.eventId,
    required this.callId,
    required this.deviceId,
    required this.occurredAt,
  });

  /// Identifies this individual message. Unique per push, even for the same
  /// call (e.g. a repeated `RING_DETECTED` for the same [callId]).
  final String eventId;

  /// Identifies the call session a `RING_DETECTED`/`RING_ENDED` pair
  /// belongs to. Correlates the two event kinds so an end only ever affects
  /// the one call it names — see [RingPresentationIntentCall] doc and
  /// `RingCallNavigationCoordinator.endCall`.
  ///
  /// On [RingDetectedEvent], defaults to [deriveLegacyCallId] of [eventId]
  /// when the backend has not sent `call_id` yet (an old
  /// `RING_DETECTED`-only sender) — see that function's doc. Such an event
  /// never receives a matching `RING_ENDED` (the legacy sender does not emit
  /// one), which remains exactly today's behavior; only the id's shape
  /// changed, not this fact.
  final String callId;

  final String deviceId;

  /// Always UTC — see the parser's timestamp validation.
  final DateTime occurredAt;
}

/// A validated `RING_DETECTED` push, decoupled from the raw FCM
/// `RemoteMessage.data` map it was parsed from.
///
/// Deliberately carries only what this minimal Fase 3B.9 slice needs.
/// [deviceId] exists for correlation/future use (e.g. per-device
/// dedup/preferences) — never shown as the notification's visible text; the
/// backend contract does not yet include a trustworthy display name.
final class RingDetectedEvent extends RingPushEvent {
  RingDetectedEvent({
    required super.eventId,
    required super.deviceId,
    required this.presentationIntent,
    required super.occurredAt,
    String? callId,
  }) : super(callId: callId ?? deriveLegacyCallId(eventId));

  final RingPresentationIntent presentationIntent;
}

/// Derives a legacy (pre-`call_id`) `RING_DETECTED`'s synthetic `call_id`
/// from its `event_id` — the single, canonical place this normalization
/// happens; every consumer ([RingCallIntent], the native Kotlin validator,
/// `RingCallTombstoneStore`, the notification id) receives the already-
/// normalized [RingDetectedEvent.callId] and never repeats this conversion.
///
/// `event_id` and `call_id` share the same 32-hex-character suffix by
/// construction (matching the backend's own fallback, interBackend PR #27):
/// `evt-<32 hex>` becomes `call-<32 hex>`, satisfying the canonical
/// `^call-[0-9a-f]{32}$` contract every consumer already enforces, instead
/// of leaking the `evt-` prefix into a field that must start with `call-`.
/// Pure and deterministic: a retried delivery of the same legacy `event_id`
/// always derives the same `call_id`.
String deriveLegacyCallId(String eventId) => 'call-${eventId.substring(4)}';

/// A validated `RING_ENDED` push: the remote counterpart to a
/// `RING_DETECTED` that shares the same [RingPushEvent.callId]. See
/// `RingCallNavigationCoordinator.endCall` and
/// `IncomingCallNotificationService.endCall` for what ending a call does
/// locally — cancelling its notification/ringtone and aborting/closing
/// `IncomingCallPage` if it is the call currently shown, and nothing at all
/// if [callId] does not match the call currently pending/active.
final class RingEndedEvent extends RingPushEvent {
  const RingEndedEvent({
    required super.eventId,
    required super.callId,
    required super.deviceId,
    required super.occurredAt,
  });
}
