import 'package:clipsync_app/withdraw/withdraw_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromRelayJson parses withdraw_notify fields', () {
    final o = WithdrawOrder.fromRelayJson({
      'type': 'withdraw_notify',
      'order_id': 'W-1',
      'amount': '100.00',
      'account': '4774090171',
      'bank': 'KBANK',
      'account_name': 'สมชาย',
      'ts': 1720000000,
    });
    expect(o.orderId, 'W-1');
    expect(o.amount, '100.00');
    expect(o.account, '4774090171');
    expect(o.bank, 'KBANK');
    expect(o.accountName, 'สมชาย');
    expect(o.ts, 1720000000);
  });

  test('fromRelayJson rejects empty order_id', () {
    expect(
      () => WithdrawOrder.fromRelayJson({'order_id': '', 'amount': '1', 'account': '1'}),
      throwsA(isA<FormatException>()),
    );
  });
}
