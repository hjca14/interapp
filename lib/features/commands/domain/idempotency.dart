import 'dart:math';

abstract interface class IdempotencyKeyGenerator {
  String generate();
}

final class SecureIdempotencyKeyGenerator implements IdempotencyKeyGenerator {
  SecureIdempotencyKeyGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String generate() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Holds a key only for one in-memory logical attempt. A retry after a
/// transport timeout reuses it; [startNew] replaces it for an explicit new
/// action, and [clear] discards it after completion/disposal. It is never
/// persisted or logged.
final class LogicalCommandAttempt {
  LogicalCommandAttempt(this._generator);

  final IdempotencyKeyGenerator _generator;
  String? _key;

  String keyForRetry() => _key ??= _generator.generate();

  String startNew() {
    _key = _generator.generate();
    return _key!;
  }

  void clear() => _key = null;
}
