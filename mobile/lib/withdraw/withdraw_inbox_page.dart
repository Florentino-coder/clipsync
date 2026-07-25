import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bank_logos.dart';
import 'withdraw_order.dart';
import 'withdraw_queue.dart';

/// In-app pending withdraw inbox (newest first). Required for Phase A ship.
class WithdrawInboxPage extends StatefulWidget {
  const WithdrawInboxPage({
    super.key,
    required this.queue,
    this.onActiveChanged,
    this.onCopied,
  });

  final WithdrawQueue queue;

  /// Called after [WithdrawQueue.setActive] so caller can refresh the notification.
  final Future<void> Function(WithdrawOrder order)? onActiveChanged;

  /// Toast / snackbar after per-row copy.
  final void Function(String label, String text)? onCopied;

  @override
  State<WithdrawInboxPage> createState() => _WithdrawInboxPageState();
}

class _WithdrawInboxPageState extends State<WithdrawInboxPage> {
  String _stateLabel(WithdrawItemState? state) {
    switch (state) {
      case WithdrawItemState.pending:
        return 'รอโอน';
      case WithdrawItemState.processing:
        return 'กำลังดำเนินการ';
      case WithdrawItemState.failed:
        return 'ไม่สำเร็จ';
      case null:
        return '';
    }
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    widget.onCopied?.call(label, text);
    if (!mounted) return;
    if (widget.onCopied == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label: $text'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onRowTap(WithdrawOrder order) async {
    widget.queue.setActive(order.orderId);
    setState(() {});
    await widget.onActiveChanged?.call(order);
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.queue.pending;
    final activeId = widget.queue.active?.orderId;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายการถอนรอโอน'),
      ),
      body: pending.isEmpty
          ? Center(
              child: Text(
                'ไม่มีรายการถอนรอโอน',
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: pending.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = pending[index];
                final canCopy = widget.queue.canCopy(order.orderId);
                final isActive = order.orderId == activeId;
                final state = widget.queue.stateOf(order.orderId);
                final name = order.accountName.trim();

                return ListTile(
                  selected: isActive,
                  leading: Image.asset(
                    bankLogoAsset(order.bank),
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_balance),
                  ),
                  title: Text(
                    '฿${order.amount}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      order.account,
                      if (name.isNotEmpty) name,
                      if (order.bank.trim().isNotEmpty) order.bank.trim(),
                      _stateLabel(state),
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'คัดลอกยอด',
                        onPressed: canCopy
                            ? () => _copy('คัดลอกยอดแล้ว', order.amount)
                            : null,
                        icon: const Icon(Icons.payments_outlined),
                      ),
                      IconButton(
                        tooltip: 'คัดลอกบัญชี',
                        onPressed: canCopy
                            ? () => _copy('คัดลอกบัญชีแล้ว', order.account)
                            : null,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ],
                  ),
                  onTap: () => unawaited(_onRowTap(order)),
                );
              },
            ),
    );
  }
}
