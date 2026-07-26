import 'package:clipsync_app/withdraw/withdraw_native_notify.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.clipsync.mobile_build/withdraw_notify');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('WithdrawNativeNotify.show sends expected map', () async {
    await WithdrawNativeNotify.show(
      orderId: 'ORD-1',
      amount: '1.00',
      account: '020323427136',
      bank: 'KBANK',
      accountName: 'ทดสอบ',
      body: '💰 ยอด: 1.00\n🏦 บัญชี: 020323427136',
      title: 'รายการถอนใหม่',
      canCopy: true,
      headsUp: true,
      pendingCount: 2,
    );

    expect(log, hasLength(1));
    expect(log.single.method, 'show');
    expect(log.single.arguments, {
      'orderId': 'ORD-1',
      'amount': '1.00',
      'account': '020323427136',
      'bank': 'KBANK',
      'accountName': 'ทดสอบ',
      'body': '💰 ยอด: 1.00\n🏦 บัญชี: 020323427136',
      'title': 'รายการถอนใหม่',
      'canCopy': true,
      'headsUp': true,
      'pendingCount': 2,
    });
  });

  test('WithdrawNativeNotify.cancel and cancelAll encode methods', () async {
    await WithdrawNativeNotify.cancel(id: 41001);
    await WithdrawNativeNotify.cancelAll();

    expect(log.map((c) => c.method), ['cancel', 'cancelAll']);
    expect(log.first.arguments, {'id': 41001});
    expect(log.last.arguments, isNull);
  });

  test('WithdrawNativeNotify.takeOpenInboxOrderId returns channel value', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'takeOpenInboxOrderId') return 'ORD-OPEN';
      return null;
    });

    final orderId = await WithdrawNativeNotify.takeOpenInboxOrderId();
    expect(orderId, 'ORD-OPEN');
    expect(log.single.method, 'takeOpenInboxOrderId');
  });
}
