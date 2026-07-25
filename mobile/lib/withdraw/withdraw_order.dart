class WithdrawOrder {
  const WithdrawOrder({
    required this.orderId,
    required this.amount,
    required this.account,
    required this.bank,
    required this.accountName,
    required this.ts,
  });

  final String orderId;
  final String amount;
  final String account;
  final String bank;
  final String accountName;
  final int ts;

  factory WithdrawOrder.fromRelayJson(Map<String, dynamic> json) {
    final orderId = (json['order_id'] as String?)?.trim() ?? '';
    if (orderId.isEmpty) {
      throw const FormatException('order_id is required');
    }
    return WithdrawOrder(
      orderId: orderId,
      amount: (json['amount'] as String?) ?? '',
      account: (json['account'] as String?) ?? '',
      bank: (json['bank'] as String?) ?? '',
      accountName: (json['account_name'] as String?) ?? '',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}
