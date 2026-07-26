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
 * Posts withdraw notifications with native copy actions.
 * Up to [MAX_VISIBLE] children share group [GROUP_KEY]; extras are cancelled on sync.
 */
object WithdrawalNotifier {
    const val CHANNEL_ID = "withdraw_alerts"
    const val CHANNEL_NAME = "Withdraw alerts"
    const val GROUP_KEY = "withdraw_pending"
    /** Legacy single-detail id (Phase A) — always cancelled on sync. */
    const val DETAIL_NOTIFY_ID = 41001
    const val SUMMARY_NOTIFY_ID = 41000
    const val MAX_VISIBLE = 20
    private const val CHILD_ID_BASE = 42000
    private const val CHILD_ID_MASK = 0x3FFF // 16384 slots

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

    private val postedChildIds = linkedSetOf<Int>()

    fun notifyIdFor(orderId: String): Int =
        CHILD_ID_BASE + (orderId.hashCode() and CHILD_ID_MASK)

    /**
     * Replace visible shade children with [items] (already capped by Dart, max [MAX_VISIBLE]).
     * Only [headsUpOrderId] may alert; others are silent updates.
     */
    fun syncVisible(
        context: Context,
        items: List<NotifyData>,
        headsUpOrderId: String?,
        pendingCount: Int,
    ) {
        ensureChannel(context)
        val nm = NotificationManagerCompat.from(context)

        // Drop legacy single-detail notify from Phase A.
        nm.cancel(DETAIL_NOTIFY_ID)

        if (items.isEmpty()) {
            for (id in postedChildIds.toList()) {
                nm.cancel(id)
            }
            postedChildIds.clear()
            nm.cancel(SUMMARY_NOTIFY_ID)
            return
        }

        val keep = linkedSetOf<Int>()
        val total = if (pendingCount > 0) pendingCount else items.size

        for (data in items) {
            val id = notifyIdFor(data.orderId)
            keep.add(id)
            val headsUp = !headsUpOrderId.isNullOrBlank() && data.orderId == headsUpOrderId
            postChild(context, nm, id, data.copy(headsUp = headsUp, pendingCount = total))
        }

        for (id in postedChildIds) {
            if (id !in keep) nm.cancel(id)
        }
        postedChildIds.clear()
        postedChildIds.addAll(keep)

        postSummary(context, nm, items, total)
    }

    /** @deprecated Prefer [syncVisible]. Kept for older Dart callers. */
    fun notify(context: Context, data: NotifyData) {
        syncVisible(
            context,
            listOf(data),
            headsUpOrderId = if (data.headsUp) data.orderId else null,
            pendingCount = data.pendingCount,
        )
    }

    fun cancel(context: Context, id: Int = DETAIL_NOTIFY_ID) {
        NotificationManagerCompat.from(context).cancel(id)
        postedChildIds.remove(id)
    }

    fun cancelAll(context: Context) {
        val nm = NotificationManagerCompat.from(context)
        nm.cancel(DETAIL_NOTIFY_ID)
        nm.cancel(SUMMARY_NOTIFY_ID)
        for (id in postedChildIds.toList()) {
            nm.cancel(id)
        }
        postedChildIds.clear()
    }

    private fun postChild(
        context: Context,
        nm: NotificationManagerCompat,
        id: Int,
        data: NotifyData,
    ) {
        val contentText = buildContentText(data)
        val contentIntent = contentPendingIntent(context, data.orderId)
        val priority = if (data.headsUp) {
            NotificationCompat.PRIORITY_HIGH
        } else {
            NotificationCompat.PRIORITY_DEFAULT
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(data.title)
            .setContentText(contentText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(data.body)
                    .setBigContentTitle(data.title),
            )
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setOnlyAlertOnce(!data.headsUp)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setGroup(GROUP_KEY)
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

        nm.notify(id, builder.build())
    }

    private fun postSummary(
        context: Context,
        nm: NotificationManagerCompat,
        items: List<NotifyData>,
        pendingCount: Int,
    ) {
        if (items.size <= 1 && pendingCount <= 1) {
            nm.cancel(SUMMARY_NOTIFY_ID)
            return
        }
        val lines = items.take(5).map { "฿${it.amount} · ${it.account}" }
        val title = "รายการถอนรอโอน · $pendingCount รายการ"
        val contentIntent = contentPendingIntent(context, items.first().orderId)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText("แตะเพื่อดูรายการ")
            .setStyle(
                NotificationCompat.InboxStyle()
                    .setBigContentTitle(title)
                    .setSummaryText("$pendingCount รายการ")
                    .also { style -> lines.forEach { style.addLine(it) } },
            )
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setNumber(pendingCount)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
        nm.notify(SUMMARY_NOTIFY_ID, builder.build())
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
