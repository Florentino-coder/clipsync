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

  testWidgets('inbox shows labeled copy TextButtons', (tester) async {
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
    expect(find.text('คัดลอกยอด'), findsOneWidget);
    expect(find.text('คัดลอกบัญชี'), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
  });

  testWidgets('tap คัดลอกยอด copies amount via callback', (tester) async {
    final q = WithdrawQueue();
    q.upsert(WithdrawOrder(
      orderId: 'W-1',
      amount: '100.00',
      account: '4774090171',
      bank: 'KBANK',
      accountName: 'สมชาย',
      ts: 1,
    ));
    String? copiedLabel;
    String? copiedText;
    await tester.pumpWidget(MaterialApp(
      home: WithdrawInboxPage(
        queue: q,
        onCopied: (label, text) {
          copiedLabel = label;
          copiedText = text;
        },
      ),
    ));
    await tester.tap(find.text('คัดลอกยอด'));
    await tester.pumpAndSettle();
    expect(copiedText, '100.00');
    expect(copiedLabel, 'คัดลอกยอดแล้ว');
  });
}
