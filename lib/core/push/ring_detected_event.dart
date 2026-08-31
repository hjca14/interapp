/// How a validated `RING_DETECTED` push should be presented locally.
///
/// Mirrors the backend's `presentation_intent` wire values exactly — see
/// [ring_detected_push_parser.dart]'s `_parsePresentationIntent`.
enum RingPresentationIntent { ringOnly, notificationOnly, ringAndNotification }

/// A validated `RING_DETECTED` push, decoupled from the raw FCM
/// `RemoteMessage.data` map it was parsed from.
///
/// Deliberately carries only what this minimal Fase 3B.9 slice needs.
/// [deviceId] exists for correlation/future use (e.g. per-device
/// dedup/preferences) — never shown as the notification's visible text; the
/// backend contract does not yet include a trustworthy display name.
final class RingDetectedEvent {
  const RingDetectedEvent({
    required this.eventId,
    required this.deviceId,
    required this.presentationIntent,
    required this.occurredAt,
  });

  final String eventId;
  final String deviceId;
  final RingPresentationIntent presentationIntent;

  /// Always UTC — see the parser's timestamp validation.
  final DateTime occurredAt;
}
