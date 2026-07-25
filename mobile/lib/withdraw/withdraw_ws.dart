import 'withdraw_order.dart';
import 'withdraw_queue.dart';

/// Process-wide queue for the FGS isolate (v1 in-memory while service alive).
class WithdrawQueueStore {
  WithdrawQueueStore._();
  static final WithdrawQueue instance = WithdrawQueue();
}

bool handleWithdrawNotifyMessage(Map<String, dynamic> msg, WithdrawQueue queue) {
  if ((msg['type'] as String?) != 'withdraw_notify') return false;
  queue.upsert(WithdrawOrder.fromRelayJson(msg));
  return true;
}
