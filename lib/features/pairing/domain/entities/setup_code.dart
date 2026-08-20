import 'dart:convert';

/// The short, human-facing onboarding code used by the QR and manual
/// fallback paths — printed/shown as e.g. `4827 1936 2051`.
///
/// Deliberately **not** the same concept as `DeviceClaim.claimCode`
/// (`features/pairing/domain/entities/device_claim.dart`): that one is the
/// product's high-entropy (≥128-bit), permanent ownership secret from
/// `docs/communication-protocol.md` §4. A 12-digit decimal code only has
/// ~40 bits of entropy — nowhere near enough to be that secret safely. This
/// is instead a short-lived, rate-limited *session* code the backend uses
/// to correlate a QR scan/manual entry to a claim attempt; seeing this
/// value does not hand out ownership by itself. See PROJECT_CONTEXT.md for
/// the full reasoning.
class SetupCode {
  const SetupCode._(this.value);

  static const length = 12;

  /// Normalized digits-only representation, always [length] characters.
  final String value;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
  static final RegExp _separators = RegExp(r'[\s-]');

  /// Accepts `482719362051`, `4827 1936 2051`, `4827-1936-2051` and
  /// normalizes to the plain digit string. Returns `null` for anything
  /// that isn't exactly [length] digits after stripping spaces/dashes —
  /// this is user-typed/scanned input, so it must never throw.
  static SetupCode? tryParse(String input) {
    final normalized = input.replaceAll(_separators, '');
    if (normalized.length != length) {
      return null;
    }
    if (!_digitsOnly.hasMatch(normalized)) {
      return null;
    }
    return SetupCode._(normalized);
  }

  /// Safe to log/send to analytics — `docs`/task rules say never log the
  /// *full* setup_code. Shows only the last 4 digits, e.g. `••••••••2051`.
  String get maskedForLogging =>
      '${''.padLeft(value.length - 4, '•')}${value.substring(value.length - 4)}';

  /// Deliberately the plain value — unlike [DeviceClaim], the user actively
  /// sees/types this in the UI, so hiding it from `toString()` would break
  /// normal display code. Logging/analytics call sites must use
  /// [maskedForLogging] instead, never this.
  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is SetupCode && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Parses a scanned QR payload into a [SetupCode].
///
/// Expected shape: `{"version": 1, "setup_code": "..."}` — `device_id` may
/// also be present for validation/diagnostics but is not required here.
/// This is a different QR from the product QR
/// (`device_claim.dart`/`docs/communication-protocol.md` §4): that one
/// carries `device_id` + the high-entropy `claim_code` printed on the unit;
/// this one carries the short onboarding `setup_code`. Returns `null` for
/// anything that doesn't parse instead of throwing, since this runs on
/// arbitrary scanned/pasted input.
SetupCode? parseSetupCodeQrPayload(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  if (decoded['version'] != 1) {
    return null;
  }
  final rawCode = decoded['setup_code'];
  if (rawCode is! String) {
    return null;
  }
  return SetupCode.tryParse(rawCode);
}
