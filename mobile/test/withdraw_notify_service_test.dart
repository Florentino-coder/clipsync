import 'package:clipsync_app/withdraw/withdraw_notify_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shouldHeadsUp when queue was empty', () {
    expect(
      shouldHeadsUp(
        wasEmpty: true,
        lastHeadsUp: DateTime(2026, 1, 1, 12, 0, 0),
        now: DateTime(2026, 1, 1, 12, 0, 1),
      ),
      isTrue,
    );
  });

  test('shouldHeadsUp when never headed up', () {
    expect(
      shouldHeadsUp(
        wasEmpty: false,
        lastHeadsUp: null,
        now: DateTime(2026, 1, 1, 12, 0, 0),
      ),
      isTrue,
    );
  });

  test('shouldHeadsUp after 4s throttle window', () {
    final last = DateTime(2026, 1, 1, 12, 0, 0);
    expect(
      shouldHeadsUp(
        wasEmpty: false,
        lastHeadsUp: last,
        now: last.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('shouldHeadsUp false within 4s window', () {
    final last = DateTime(2026, 1, 1, 12, 0, 0);
    expect(
      shouldHeadsUp(
        wasEmpty: false,
        lastHeadsUp: last,
        now: last.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });
}
