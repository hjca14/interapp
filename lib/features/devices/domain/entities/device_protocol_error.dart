/// The v1 error codes a command response or backend call can report, per
/// `docs/communication-protocol.md` §21.
///
/// A closed enum (not an open wrapper like [IntercomState]) because the
/// protocol fully enumerates this vocabulary. [unknown] only exists so a
/// future code the app doesn't recognize yet degrades gracefully instead of
/// throwing during parsing.
enum DeviceProtocolError {
  invalidPayload,
  unsupportedProtocolVersion,
  unknownCommand,
  commandNotAllowed,
  deviceBusy,
  notProvisioned,
  wifiUnavailable,
  cloudUnavailable,
  doorOutputFailure,
  otaDownloadFailed,
  otaValidationFailed,
  otaInstallFailed,
  internalError,

  /// A code the app doesn't recognize (future protocol addition, or a bug
  /// upstream) — never thrown, always represented explicitly so the UI can
  /// show a generic message instead of crashing.
  unknown;

  static const Map<String, DeviceProtocolError> _byWireValue = {
    'INVALID_PAYLOAD': invalidPayload,
    'UNSUPPORTED_PROTOCOL_VERSION': unsupportedProtocolVersion,
    'UNKNOWN_COMMAND': unknownCommand,
    'COMMAND_NOT_ALLOWED': commandNotAllowed,
    'DEVICE_BUSY': deviceBusy,
    'NOT_PROVISIONED': notProvisioned,
    'WIFI_UNAVAILABLE': wifiUnavailable,
    'CLOUD_UNAVAILABLE': cloudUnavailable,
    'DOOR_OUTPUT_FAILURE': doorOutputFailure,
    'OTA_DOWNLOAD_FAILED': otaDownloadFailed,
    'OTA_VALIDATION_FAILED': otaValidationFailed,
    'OTA_INSTALL_FAILED': otaInstallFailed,
    'INTERNAL_ERROR': internalError,
  };

  /// Parses the wire code from a command response's `error.code`. Anything
  /// unrecognized (including `null`) becomes [unknown] rather than throwing.
  static DeviceProtocolError fromWireCode(String? code) {
    return _byWireValue[code] ?? unknown;
  }
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
    case DeviceProtocolError.doorOutputFailure:
      return 'Não foi possível acionar a abertura da porta.';
    case DeviceProtocolError.invalidPayload:
    case DeviceProtocolError.unknownCommand:
    case DeviceProtocolError.unsupportedProtocolVersion:
    case DeviceProtocolError.internalError:
    case DeviceProtocolError.otaDownloadFailed:
    case DeviceProtocolError.otaValidationFailed:
    case DeviceProtocolError.otaInstallFailed:
    case DeviceProtocolError.unknown:
      return 'Algo deu errado. Tente novamente mais tarde.';
  }
}
