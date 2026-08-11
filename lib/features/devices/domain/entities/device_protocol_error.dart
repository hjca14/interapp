/// The v1 error codes a command response or backend call can report, per
/// `docs/communication-protocol.md` §21.
///
/// A closed enum (not an open wrapper like [IntercomState]) because the
/// protocol fully enumerates this vocabulary. [unknown] only exists so a
/// future code the app doesn't recognize yet degrades gracefully instead of
/// throwing during parsing.
enum DeviceProtocolError {
  invalidPayload,
  payloadTooLarge,
  unsupportedProtocolVersion,
  unknownCommand,
  commandNotAllowed,
  commandExpired,
  clockNotTrustworthy,
  invalidTimestamp,
  deviceBusy,
  notProvisioned,
  wifiUnavailable,
  cloudUnavailable,
  doorOutputFailure,
  otaDownloadFailed,
  otaValidationFailed,
  otaInstallFailed,
  provisioningFailed,
  internalError,

  /// A code the app doesn't recognize (future protocol addition, or a bug
  /// upstream) — never thrown, always represented explicitly so the UI can
  /// show a generic message instead of crashing.
  unknown;

  static const Map<String, DeviceProtocolError> _byWireValue = {
    'INVALID_PAYLOAD': invalidPayload,
    'PAYLOAD_TOO_LARGE': payloadTooLarge,
    'UNSUPPORTED_PROTOCOL_VERSION': unsupportedProtocolVersion,
    'UNKNOWN_COMMAND': unknownCommand,
    'COMMAND_NOT_ALLOWED': commandNotAllowed,
    'COMMAND_EXPIRED': commandExpired,
    'CLOCK_NOT_TRUSTWORTHY': clockNotTrustworthy,
    'INVALID_TIMESTAMP': invalidTimestamp,
    'DEVICE_BUSY': deviceBusy,
    'NOT_PROVISIONED': notProvisioned,
    'WIFI_UNAVAILABLE': wifiUnavailable,
    'CLOUD_UNAVAILABLE': cloudUnavailable,
    'DOOR_OUTPUT_FAILURE': doorOutputFailure,
    'OTA_DOWNLOAD_FAILED': otaDownloadFailed,
    'OTA_VALIDATION_FAILED': otaValidationFailed,
    'OTA_INSTALL_FAILED': otaInstallFailed,
    'PROVISIONING_FAILED': provisioningFailed,
    'INTERNAL_ERROR': internalError,
  };

  /// Parses the wire code from a command response's `error.code`. Anything
  /// unrecognized (including `null`) becomes [unknown] rather than throwing.
  /// The original string is not preserved here — callers that need it for
  /// diagnostics should keep the raw `error.code`/`error.message` alongside
  /// this parsed value rather than relying on [unknown] to carry it.
  static DeviceProtocolError fromWireCode(String? code) {
    return _byWireValue[code] ?? unknown;
  }

  /// Which layer this error semantically originates from. This is an
  /// **app-side classification for handling/diagnostics only** — it does
  /// not change or reinterpret the wire codes themselves (§21 defines those
  /// exhaustively), it just groups them so the UI/logging can treat
  /// device-reported problems differently from connectivity problems.
  DeviceProtocolErrorOrigin get origin {
    switch (this) {
      case cloudUnavailable:
        return DeviceProtocolErrorOrigin.connectivity;
      case internalError:
      case unknown:
        return DeviceProtocolErrorOrigin.backend;
      case invalidPayload:
      case payloadTooLarge:
      case unsupportedProtocolVersion:
      case unknownCommand:
      case commandNotAllowed:
      case commandExpired:
      case clockNotTrustworthy:
      case invalidTimestamp:
      case deviceBusy:
      case notProvisioned:
      case wifiUnavailable:
      case doorOutputFailure:
      case otaDownloadFailed:
      case otaValidationFailed:
      case otaInstallFailed:
      case provisioningFailed:
        return DeviceProtocolErrorOrigin.device;
    }
  }
}

/// Which layer reported a [DeviceProtocolError] — see
/// [DeviceProtocolError.origin]. Not part of the wire contract; a purely
/// app-side grouping for handling/diagnostics.
enum DeviceProtocolErrorOrigin {
  /// The InterBridge firmware itself made this decision (validation,
  /// hardware failure, its own Wi-Fi/clock state, etc.).
  device,

  /// The application backend reported this without a device-originated
  /// answer (e.g. it never received a terminal response, or hit its own
  /// internal fault).
  backend,

  /// Nothing could be reached at all — the app/backend couldn't talk to
  /// the cloud in the first place, so there is no device-reported answer to
  /// classify.
  connectivity,
}

/// Maps a [DeviceProtocolError] to a short, user-facing message in
/// Portuguese.
///
/// This intentionally never surfaces the protocol's diagnostic `message`
/// string (see the `error.message` field in
/// `docs/communication-protocol.md` §19) — that text is meant for logs/
/// support, not end users, and could leak implementation detail. The UI
/// always goes through this mapping instead.
String deviceProtocolErrorMessage(DeviceProtocolError error) {
  switch (error) {
    case DeviceProtocolError.notProvisioned:
      return 'Este InterBridge ainda não está configurado.';
    case DeviceProtocolError.cloudUnavailable:
      return 'Não foi possível falar com o InterBridge agora. Tente novamente em instantes.';
    case DeviceProtocolError.wifiUnavailable:
      return 'O InterBridge está sem conexão de rede.';
    case DeviceProtocolError.deviceBusy:
      return 'O InterBridge está ocupado com outra operação. Tente novamente.';
    case DeviceProtocolError.commandNotAllowed:
      return 'Essa ação não é permitida para este dispositivo.';
    case DeviceProtocolError.commandExpired:
      return 'O comando expirou antes de ser executado. Tente novamente.';
    case DeviceProtocolError.clockNotTrustworthy:
      return 'O InterBridge não conseguiu confirmar o horário atual. Tente novamente em instantes.';
    case DeviceProtocolError.doorOutputFailure:
      return 'Não foi possível acionar a abertura da porta.';
    case DeviceProtocolError.provisioningFailed:
      return 'Não foi possível parear o InterBridge. Tente novamente.';
    case DeviceProtocolError.invalidPayload:
    case DeviceProtocolError.payloadTooLarge:
    case DeviceProtocolError.unknownCommand:
    case DeviceProtocolError.unsupportedProtocolVersion:
    case DeviceProtocolError.invalidTimestamp:
    case DeviceProtocolError.internalError:
    case DeviceProtocolError.otaDownloadFailed:
    case DeviceProtocolError.otaValidationFailed:
    case DeviceProtocolError.otaInstallFailed:
    case DeviceProtocolError.unknown:
      return 'Algo deu errado. Tente novamente mais tarde.';
  }
}
