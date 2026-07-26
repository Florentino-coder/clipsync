package com.clipsync.mobile_build.withdraw

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.clipsync.mobile_build.MainActivity

/**
 * Posts withdraw detail notifications with native copy actions (Phase A).
 * Clipboard values live in PendingIntent extras so copy works when Flutter is paused/dead.
 */
object WithdrawalNotifier {
    const val CHANNEL_ID = "withdraw_alerts"
    const val CHANNEL_NAME = "Withdraw alerts"
    const val DETAIL_NOTIFY_ID = 41001

    data class NotifyData(
        val orderId: String,
        val amount: String,
        val account: String,
        val bank: String = "",
        val accountName: String = "",
        val body: String,
        val title: String = "รายการถอนใหม่",
        val canCopy: Boolean = true,
        val headsUp: Boolean = true,
        val pendingCount: Int = 1,
    )

    fun notify(context: Context, data: NotifyData) {
        ensureChannel(context)

        val contentText = buildContentText(data)
        val contentIntent = contentPendingIntent(context, data.orderId)

        val priority = if (data.headsUp) {
            NotificationCompat.PRIORITY_HIGH
        } else {
            NotificationCompat.PRIORITY_LOW
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(data.title)
            .setContentText(contentText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(data.body)
                    .setBigContentTitle(data.title)
                    .setSummaryText(
                        if (data.pendingCount > 1) "${data.pendingCount} รายการ" else null,
                    ),
            )
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setOnlyAlertOnce(!data.headsUp)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setGroup("withdraw_pending")
            .setNumber(data.pendingCount)
            .setPriority(priority)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (data.canCopy) {
            if (data.amount.isNotBlank()) {
                builder.addAction(
                    0,
                    "คัดลอกยอด",
                    copyPendingIntent(
                        context,
                        data.orderId,
                        ClipboardCopyReceiver.TYPE_AMOUNT,
                        data.amount,
                    ),
                )
            }
            if (data.account.isNotBlank()) {
                builder.addAction(
                    0,
                    "คัดลอกบัญชี",
                    copyPendingIntent(
                        context,
                        data.orderId,
                        ClipboardCopyReceiver.TYPE_ACCOUNT,
                        data.account,
                    ),
                )
            }
        }

        NotificationManagerCompat.from(context).notify(DETAIL_NOTIFY_ID, builder.build())
    }

    fun cancel(context: Context, id: Int = DETAIL_NOTIFY_ID) {
        NotificationManagerCompat.from(context).cancel(id)
    }

    fun cancelAll(context: Context) {
        NotificationManagerCompat.from(context).cancel(DETAIL_NOTIFY_ID)
    }

    private fun buildContentText(data: NotifyData): String {
        val firstLine = data.body.lineSequence().firstOrNull()?.trim().orEmpty()
        if (firstLine.isNotEmpty()) return firstLine
        return "฿${data.amount} · ${data.account}"
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Pending withdraw order alerts"
        }
        manager.createNotificationChannel(channel)
    }

    private fun copyPendingIntent(
        context: Context,
        orderId: String,
        type: String,
        value: String,
    ): PendingIntent {
        val intent = Intent(context, ClipboardCopyReceiver::class.java).apply {
            action = ClipboardCopyReceiver.ACTION_COPY
            putExtra(ClipboardCopyReceiver.EXTRA_TYPE, type)
            putExtra(ClipboardCopyReceiver.EXTRA_VALUE, value)
        }
        val requestCode = "$orderId:$type".hashCode()
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun contentPendingIntent(context: Context, orderId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_WITHDRAW_INBOX, true)
            putExtra(EXTRA_ORDER_ID, orderId)
        }
        val requestCode = "open:$orderId".hashCode()
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    const val EXTRA_OPEN_WITHDRAW_INBOX = "open_withdraw_inbox"
    const val EXTRA_ORDER_ID = "order_id"
}
