import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart API for native Android withdraw shade notifications (Phase A).
///
/// Copy actions are handled entirely in Kotlin via ClipboardCopyReceiver;
/// this channel only posts/cancels notifications and reads body-tap launch extras.
class WithdrawNativeNotify {
  WithdrawNativeNotify._();

  static const MethodChannel channel = MethodChannel(
    'com.clipsync.mobile_build/withdraw_notify',
  );

  static bool _listening = false;

  /// Listen for native body-tap events while the Flutter UI is already running.
  static void ensureOpenInboxListener(void Function(String orderId) onOpen) {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenWithdrawInbox') {
        final id = '${call.arguments ?? ''}'.trim();
        if (id.isNotEmpty) onOpen(id);
      }
      return null;
    });
  }

  /// Post (or replace) the detail withdraw notification on Android.
  /// No-op when the platform plugin is missing.
  static Future<void> show({
    required String orderId,
    required String amount,
    required String account,
    String bank = '',
    String accountName = '',
    required String body,
    String title = 'รายการถอนใหม่',
    bool canCopy = true,
    bool headsUp = true,
    int pendingCount = 1,
  }) async {
    if (kIsWeb) return;
    try {
      await channel.invokeMethod<void>('show', <String, Object?>{
        'orderId': orderId,
        'amount': amount,
        'account': account,
        'bank': bank,
        'accountName': accountName,
        'body': body,
        'title': title,
        'canCopy': canCopy,
        'headsUp': headsUp,
        'pendingCount': pendingCount,
      });
    } on MissingPluginException {
      // Desktop/tests without the Android plugin registered.
    }
  }

  static Future<void> cancel({int id = 41001}) async {
    if (kIsWeb) return;
    try {
      await channel.invokeMethod<void>('cancel', <String, Object?>{'id': id});
    } on MissingPluginException {
      // ignore
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // ignore
    }
  }

  /// Consume a pending body-tap order id from MainActivity intent extras.
  static Future<String?> takeOpenInboxOrderId() async {
    if (kIsWeb) return null;
    try {
      final raw = await channel.invokeMethod<String?>('takeOpenInboxOrderId');
      final id = raw?.trim() ?? '';
      return id.isEmpty ? null : id;
    } on MissingPluginException {
      return null;
    }
  }
}
