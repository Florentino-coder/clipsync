import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'withdraw_queue.dart';

const kWithdrawDetailNotifyId = 41001;
const kWithdrawSummaryNotifyId = 41000;
const kWithdrawChannelId = 'withdraw_alerts';
const kWithdrawChannelName = 'Withdraw alerts';
const kCopyAmountActionId = 'copy_amount';
const kCopyAccountActionId = 'copy_account';

/// Pure throttle helper — full heads-up if queue was empty or last heads-up ≥4s ago.
bool shouldHeadsUp({
  required bool wasEmpty,
  required DateTime? lastHeadsUp,
  required DateTime now,
}) {
  if (wasEmpty) return true;
  if (lastHeadsUp == null) return true;
  return now.difference(lastHeadsUp) >= const Duration(seconds: 4);
}

String encodeWithdrawNotifyPayload({
  required String orderId,
  required String amount,
  required String account,
}) {
  return jsonEncode({
    'order_id': orderId,
    'amount': amount,
    'account': account,
  });
}

Map<String, String>? decodeWithdrawNotifyPayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    String read(String k) => '${decoded[k] ?? ''}'.trim();
    final out = {
      'order_id': read('order_id'),
      'amount': read('amount'),
      'account': read('account'),
    };
    if (out['amount']!.isEmpty && out['account']!.isEmpty) return null;
    return out;
  } catch (_) {
    final id = raw.trim();
    if (id.isEmpty) return null;
    return {'order_id': id, 'amount': '', 'account': ''};
  }
}

String? copyTextForAction(String? actionId, Map<String, String> data) {
  if (actionId == kCopyAmountActionId) {
    final t = data['amount']?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
  if (actionId == kCopyAccountActionId) {
    final t = data['account']?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
  return null;
}

String formatWithdrawNotifyBody({
  required String amount,
  required String account,
  required String bank,
  required String accountName,
}) {
  final bankLabel = bank.trim().isEmpty ? '—' : bank.trim();
  final name = accountName.trim();
  final bankNameLine = name.isEmpty ? bankLabel : '$bankLabel · $name';
  return 'ยอด: $amount\nบัญชี: $account\n$bankNameLine';
}

typedef CopyHandler = Future<void> Function(String actionId, String text);

/// Called when user taps the withdraw notification body (not a copy action).
/// [orderId] comes from notification payload when available.
typedef OpenInboxHandler = void Function(String? orderId);

/// Injectable queue accessor for notification copy actions.
WithdrawQueue Function()? withdrawQueueProvider;

/// Open-inbox handler registered by the main UI (HomeScreen).
OpenInboxHandler? onOpenWithdrawInbox;

/// Local notifications for pending withdraw orders (HIGH channel, separate from FGS).
class WithdrawNotifyService {
  WithdrawNotifyService({
    FlutterLocalNotificationsPlugin? plugin,
    CopyHandler? onCopy,
    DateTime Function()? clock,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onCopy = onCopy,
        _clock = clock ?? DateTime.now;

  static final WithdrawNotifyService instance = WithdrawNotifyService();

  final FlutterLocalNotificationsPlugin _plugin;
  final CopyHandler? _onCopy;
  final DateTime Function() _clock;

  DateTime? _lastHeadsUp;
  bool _initialized = false;

  DateTime? get lastHeadsUp => _lastHeadsUp;

  @visibleForTesting
  void setLastHeadsUpForTest(DateTime? value) => _lastHeadsUp = value;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          withdrawNotifyBackgroundResponse,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        kWithdrawChannelId,
        kWithdrawChannelName,
        description: 'Pending withdraw order alerts',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Sync detail (+ summary when pending > 1) from [q].
  /// Pass [wasEmpty] as the queue empty-state *before* the upsert that triggered sync.
  Future<void> syncFromQueue(
    WithdrawQueue q, {
    required bool allowHeadsUp,
    bool wasEmpty = false,
  }) async {
    await init();

    final pending = q.pending;
    if (pending.isEmpty) {
      await _plugin.cancel(kWithdrawDetailNotifyId);
      await _plugin.cancel(kWithdrawSummaryNotifyId);
      return;
    }

    final active = q.active;
    if (active == null) return;

    final now = _clock();
    final headsUp = allowHeadsUp &&
        shouldHeadsUp(
          wasEmpty: wasEmpty,
          lastHeadsUp: _lastHeadsUp,
          now: now,
        );
    if (headsUp) {
      _lastHeadsUp = now;
    }

    final bankLabel = active.bank.trim().isEmpty ? '—' : active.bank.trim();
    final namePart = active.accountName.trim();
    final bankNameLine =
        namePart.isEmpty ? bankLabel : '$bankLabel · $namePart';
    final body = '฿${active.amount}\n${active.account}\n$bankNameLine';

    final canCopy = q.canCopy(active.orderId);
    final actions = canCopy
        ? <AndroidNotificationAction>[
            const AndroidNotificationAction(
              kCopyAmountActionId,
              'คัดลอกยอด',
              showsUserInterface: false,
              cancelNotification: false,
            ),
            const AndroidNotificationAction(
              kCopyAccountActionId,
              'คัดลอกบัญชี',
              showsUserInterface: false,
              cancelNotification: false,
            ),
          ]
        : <AndroidNotificationAction>[];

    final importance = headsUp ? Importance.high : Importance.low;
    final priority = headsUp ? Priority.high : Priority.low;

    final androidDetails = AndroidNotificationDetails(
      kWithdrawChannelId,
      kWithdrawChannelName,
      channelDescription: 'Pending withdraw order alerts',
      importance: importance,
      priority: priority,
      category: AndroidNotificationCategory.status,
      actions: actions,
      groupKey: 'withdraw_pending',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: 'รายการถอนใหม่',
        summaryText: pending.length > 1 ? '${pending.length} รายการ' : null,
      ),
      onlyAlertOnce: !headsUp,
      number: pending.length,
    );

    await _plugin.show(
      kWithdrawDetailNotifyId,
      'รายการถอนใหม่',
      body,
      NotificationDetails(android: androidDetails),
      payload: active.orderId,
    );

    if (pending.length > 1) {
      final summaryAndroid = AndroidNotificationDetails(
        kWithdrawChannelId,
        kWithdrawChannelName,
        channelDescription: 'Pending withdraw order alerts',
        importance: Importance.low,
        priority: Priority.low,
        groupKey: 'withdraw_pending',
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          pending.take(5).map((o) => '฿${o.amount} · ${o.account}').toList(),
          contentTitle: 'รายการถอนรอโอน · ${pending.length} รายการ',
          summaryText: '${pending.length} รายการ',
        ),
        onlyAlertOnce: true,
      );
      await _plugin.show(
        kWithdrawSummaryNotifyId,
        'รายการถอนรอโอน · ${pending.length} รายการ',
        'แตะเพื่อดูรายการ',
        NotificationDetails(android: summaryAndroid),
        payload: active.orderId,
      );
    } else {
      await _plugin.cancel(kWithdrawSummaryNotifyId);
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    unawaited(_handleAction(response));
  }

  Future<void> _handleAction(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;

    // Body tap (no action) → set active from payload + open inbox.
    if (actionId == null || actionId.isEmpty) {
      final q = withdrawQueueProvider?.call();
      final orderId = (payload ?? '').trim();
      if (q != null && orderId.isNotEmpty) {
        q.setActive(orderId);
        try {
          await syncFromQueue(q, allowHeadsUp: false);
        } catch (_) {}
      }
      final open = onOpenWithdrawInbox;
      if (open != null) {
        open(orderId.isEmpty ? null : orderId);
      } else {
        FlutterForegroundTask.sendDataToMain({
          'type': 'open_withdraw_inbox',
          if (orderId.isNotEmpty) 'order_id': orderId,
        });
      }
      return;
    }

    if (actionId != kCopyAmountActionId && actionId != kCopyAccountActionId) {
      return;
    }

    final q = withdrawQueueProvider?.call();
    if (q == null) return;

    final text = actionId == kCopyAmountActionId
        ? q.copyAmountText()
        : q.copyAccountText();
    if (text == null || text.isEmpty) return;

    if (_onCopy != null) {
      await _onCopy!(actionId, text);
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    FlutterForegroundTask.sendDataToMain({
      'type': 'withdraw_copy',
      'action': actionId,
      'text': text,
    });
  }

  /// If the app was launched by tapping a withdraw notification, open inbox.
  Future<void> handleLaunchDetails() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return;
    final response = details!.notificationResponse;
    if (response == null) return;
    // Only body taps open inbox (copy actions already handled separately).
    final actionId = response.actionId;
    if (actionId != null && actionId.isNotEmpty) return;
    await _handleAction(response);
  }
}

@pragma('vm:entry-point')
void withdrawNotifyBackgroundResponse(NotificationResponse response) {
  // Queue lives in FGS/main isolates; foreground callback handles copy when alive.
}
