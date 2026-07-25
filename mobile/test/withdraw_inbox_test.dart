import 'package:clipsync_app/withdraw/withdraw_inbox_page.dart';
import 'package:clipsync_app/withdraw/withdraw_order.dart';
import 'package:clipsync_app/withdraw/withdraw_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox lists pending order', (tester) async {
    final q = WithdrawQueue();
    q.upsert(WithdrawOrder(
      orderId: 'W-1',
      amount: '100.00',
      account: '4774090171',
      bank: 'KBANK',
      accountName: 'สมชาย',
      ts: 1,
    ));
    await tester.pumpWidget(MaterialApp(home: WithdrawInboxPage(queue: q)));
    expect(find.textContaining('100.00'), findsWidgets);
    expect(find.textContaining('4774090171'), findsWidgets);
  });

  testWidgets('inbox empty state shows Thai copy', (tester) async {
    final q = WithdrawQueue();
    await tester.pumpWidget(MaterialApp(home: WithdrawInboxPage(queue: q)));
    expect(find.text('ไม่มีรายการถอนรอโอน'), findsOneWidget);
  });
}
