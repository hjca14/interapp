/// Sanitized HTTP/API failure categories exposed to repositories and UI.
enum ApiFailureKind {
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  server,
  unavailable,
  timeout,
  offline,
  invalidResponse,
}

/// Typed API failure that never includes sensitive response bodies.
class ApiFailure implements Exception {
  const ApiFailure(this.kind, this.message, {this.requestId, this.retryAfter});

  final ApiFailureKind kind;
  final String message;
  final String? requestId;
  final Duration? retryAfter;

  @override
  String toString() => message;
}
