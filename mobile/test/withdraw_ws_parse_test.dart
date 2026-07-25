import 'package:clipsync_app/withdraw/withdraw_queue.dart';
import 'package:clipsync_app/withdraw/withdraw_ws.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handleWithdrawNotifyMessage upserts into queue', () {
    final q = WithdrawQueue();
    final ok = handleWithdrawNotifyMessage({
      'type': 'withdraw_notify',
      'order_id': 'W-1',
      'amount': '100.00',
      'account': '4774090171',
      'bank': 'KBANK',
      'account_name': '',
      'ts': 1,
    }, q);
    expect(ok, isTrue);
    expect(q.active?.orderId, 'W-1');
  });

  test('ignores clip messages', () {
    final q = WithdrawQueue();
    expect(handleWithdrawNotifyMessage({'type': 'clip', 'text': 'hi'}, q), isFalse);
    expect(q.pending, isEmpty);
  });
}
