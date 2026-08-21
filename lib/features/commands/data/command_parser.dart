import '../../../core/network/api_failure.dart';
import '../domain/command_models.dart';

/// Pure parsing kept independent from HTTP and repository decisions.
final class CommandParser {
  const CommandParser();

  AcceptedCommand parseAccepted(Map<String, dynamic> json) {
    try {
      final state = _state(json['state']);
      if (state != CommandState.pending) {
        throw const FormatException('Accepted command must be PENDING');
      }
      return AcceptedCommand(
        commandId: CommandId(_string(json, 'command_id')),
        issuedAt: UtcTimestamp.parse(_string(json, 'issued_at')),
        expiresAt: UtcTimestamp.parse(_string(json, 'expires_at')),
      );
    } on FormatException {
      throw _invalidResponse();
    } on TypeError {
      throw _invalidResponse();
    }
  }

  CommandStatus parseStatus(Map<String, dynamic> json) {
    try {
      final state = _state(json['state']);
      CommandRejection? rejection;
      if (state == CommandState.rejected) {
        final raw = json['rejection'];
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Missing rejection');
        }
        rejection = CommandRejection(_string(raw, 'code'));
      }
      return CommandStatus(
        commandId: CommandId(_string(json, 'command_id')),
        state: state,
        rejection: rejection,
      );
    } on FormatException {
      throw _invalidResponse();
    } on TypeError {
      throw _invalidResponse();
    }
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  static CommandState _state(Object? value) => switch (value) {
    'PENDING' => CommandState.pending,
    'COMPLETED' => CommandState.completed,
    'REJECTED' => CommandState.rejected,
    'EXPIRED' => CommandState.expired,
    _ => throw const FormatException('Unknown state'),
  };

  static ApiFailure _invalidResponse() => const ApiFailure(
    ApiFailureKind.invalidResponse,
    'A resposta do serviço é inválida.',
  );
}
