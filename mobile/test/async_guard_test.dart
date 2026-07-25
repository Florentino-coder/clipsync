import 'dart:async';

import 'package:clipsync_app/async_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('awaitGuarded returns when future completes in time', () async {
    final result = await awaitGuarded(
      Future<int>.value(7),
      timeout: const Duration(milliseconds: 200),
    );
    expect(result, 7);
  });

  test('awaitGuarded completes null when future never finishes', () async {
    final never = Completer<int>();
    final started = DateTime.now();
    final result = await awaitGuarded(
      never.future,
      timeout: const Duration(milliseconds: 50),
    );
    final elapsed = DateTime.now().difference(started);
    expect(result, isNull);
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('awaitGuarded returns null on thrown error', () async {
    final result = await awaitGuarded(
      Future<int>.error(StateError('boom')),
      timeout: const Duration(seconds: 1),
    );
    expect(result, isNull);
  });

  test('awaitGuardedVoid finishes even if close hangs', () async {
    final never = Completer<void>();
    final started = DateTime.now();
    await awaitGuardedVoid(
      never.future,
      timeout: const Duration(milliseconds: 50),
    );
    final elapsed = DateTime.now().difference(started);
    expect(elapsed.inMilliseconds, lessThan(500));
  });
}
