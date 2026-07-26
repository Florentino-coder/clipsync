package com.clipsync.mobile_build.withdraw

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.Toast

/**
 * Copies withdraw amount/account from PendingIntent extras to the system clipboard.
 * Values are embedded in the intent — no Dart/Flutter process required.
 */
class ClipboardCopyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_COPY) return
        val value = intent.getStringExtra(EXTRA_VALUE)?.trim().orEmpty()
        if (value.isEmpty()) return

        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return
        val label = intent.getStringExtra(EXTRA_TYPE) ?: "withdraw"
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value))

        // Android 12+ shows a system clipboard indicator; custom toast is redundant/noisy.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            Toast.makeText(context, "คัดลอกแล้ว", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        const val ACTION_COPY = "com.clipsync.mobile_build.withdraw.COPY"
        const val EXTRA_TYPE = "type"
        const val EXTRA_VALUE = "value"
        const val TYPE_AMOUNT = "amount"
        const val TYPE_ACCOUNT = "account"
    }
}
