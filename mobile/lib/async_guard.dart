import 'dart:async';

/// Awaits [future] up to [timeout], returning the value or `null` on
/// timeout / error so callers can always continue cleanup and clear UI busy.
Future<T?> awaitGuarded<T>(
  Future<T> future, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    return await future.timeout(timeout);
  } catch (_) {
    return null;
  }
}

/// Like [awaitGuarded] for void futures (close / cancel / stop).
Future<void> awaitGuardedVoid(
  Future<void>? future, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (future == null) {
    return;
  }
  try {
    await future.timeout(timeout);
  } catch (_) {
    // Best-effort cleanup — never block UI on hung closes.
  }
}
