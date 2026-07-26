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

  test('encodeWithdrawNotifyPayload round-trips active fields', () {
    final json = encodeWithdrawNotifyPayload(
      orderId: 'ORD-1',
      amount: '1.00',
      account: '020323427136',
    );
    final parsed = decodeWithdrawNotifyPayload(json);
    expect(parsed?['order_id'], 'ORD-1');
    expect(parsed?['amount'], '1.00');
    expect(parsed?['account'], '020323427136');
  });

  test('decodeWithdrawNotifyPayload accepts legacy plain order id', () {
    final parsed = decodeWithdrawNotifyPayload('ORD-LEGACY');
    expect(parsed?['order_id'], 'ORD-LEGACY');
    expect(parsed?['amount'], '');
    expect(parsed?['account'], '');
  });

  test('copyTextForAction picks amount or account', () {
    final data = {
      'order_id': 'ORD-1',
      'amount': '1.00',
      'account': '020323427136',
    };
    expect(copyTextForAction(kCopyAmountActionId, data), '1.00');
    expect(copyTextForAction(kCopyAccountActionId, data), '020323427136');
    expect(copyTextForAction('other', data), isNull);
  });

  test('formatWithdrawNotifyBody uses brief labels', () {
    final body = formatWithdrawNotifyBody(
      amount: '1.00',
      account: '020323427136',
      bank: 'GSB',
      accountName: 'ทดสอบ',
    );
    expect(body, contains('ยอด: 1.00'));
    expect(body, contains('บัญชี: 020323427136'));
    expect(body, contains('GSB'));
    expect(body, contains('ทดสอบ'));
  });

  test('resolveWithdrawCopyText prefers payload over queue', () {
    final payload = encodeWithdrawNotifyPayload(
      orderId: 'ORD-1',
      amount: '1.00',
      account: '020323427136',
    );
    expect(
      resolveWithdrawCopyText(
        actionId: kCopyAmountActionId,
        payload: payload,
        queueAmount: '99.99',
        queueAccount: '111111111111',
      ),
      '1.00',
    );
    expect(
      resolveWithdrawCopyText(
        actionId: kCopyAccountActionId,
        payload: payload,
        queueAmount: '99.99',
        queueAccount: '111111111111',
      ),
      '020323427136',
    );
  });

  test('resolveWithdrawCopyText falls back to queue for legacy payload', () {
    expect(
      resolveWithdrawCopyText(
        actionId: kCopyAmountActionId,
        payload: 'ORD-LEGACY',
        queueAmount: '5.00',
        queueAccount: '999999999999',
      ),
      '5.00',
    );
    expect(
      resolveWithdrawCopyText(
        actionId: kCopyAccountActionId,
        payload: 'ORD-LEGACY',
        queueAmount: '5.00',
        queueAccount: '999999999999',
      ),
      '999999999999',
    );
  });
}
