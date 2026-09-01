import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

/// A minimal, sanitized record of one authentication operation failure —
/// safe to log. Carries only a code-controlled [operation] name and the
/// exception's own [AuthException.runtimeTypeName] as [failureType] — never
/// `message`, `recoverySuggestion`, `underlyingException`, or any argument
/// (email, password, code, token, user attribute, raw payload).
@immutable
class AuthDiagnostic {
  const AuthDiagnostic({required this.operation, required this.failureType});

  final String operation;
  final String failureType;

  String toLogLine() => '[AUTH] operation=$operation failure_type=$failureType';
}

/// Emits [exception]'s sanitized [AuthDiagnostic] for [operation] through
/// [sink] (defaults to [debugPrint]), but only when [debugMode] is true.
///
/// [debugMode] defaults to [kDebugMode] but is taken as a parameter rather
/// than read directly in the body: `kDebugMode` is always `true` while
/// running `flutter test`, so there is no way to exercise the release path
/// through that constant. This parameter is the extracted, independently
/// testable decision point that proves the release path emits nothing.
///
/// Centralized here — never scattered as ad hoc `debugPrint` calls across
/// auth pages — so every authentication operation logs the same shape.
void emitAuthDiagnostic(
  String operation,
  AuthException exception, {
  bool debugMode = kDebugMode,
  void Function(String? message, {int? wrapWidth})? sink,
}) {
  if (!debugMode) {
    return;
  }
  (sink ?? debugPrint)(
    AuthDiagnostic(
      operation: operation,
      failureType: exception.runtimeTypeName,
    ).toLogLine(),
  );
}
