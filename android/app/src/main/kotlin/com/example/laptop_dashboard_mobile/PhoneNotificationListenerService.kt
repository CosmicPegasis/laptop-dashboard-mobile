package com.example.laptop_dashboard_mobile

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.EventChannel

object NotificationSyncBridge {
    var eventSink: EventChannel.EventSink? = null

    fun isNotificationAccessEnabled(context: Context): Boolean {
        val packageName = context.packageName
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val componentName = ComponentName(context, PhoneNotificationListenerService::class.java)
        return flat.split(":")
            .mapNotNull { ComponentName.unflattenFromString(it) }
            .any { it.packageName == packageName && it.className == componentName.className }
    }
}

class PhoneNotificationListenerService : NotificationListenerService() {
    private val TAG = "PhoneNotificationSvc"

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationListenerService connected and ready")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) {
            return
        }

        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString().orEmpty().trim()
        val text = extras.getCharSequence("android.text")?.toString().orEmpty().trim()
        val bigText = extras.getCharSequence("android.bigText")?.toString().orEmpty().trim()
        val message = if (bigText.isNotEmpty()) bigText else text

        val payload = hashMapOf<String, Any>(
            "package_name" to sbn.packageName,
            "title" to title,
            "text" to message,
            "posted_at" to sbn.postTime,
            "is_ongoing" to sbn.isOngoing
        )

        val sink = NotificationSyncBridge.eventSink
        if (sink != null) {
            Log.d(TAG, "Forwarding notification from ${sbn.packageName}: $title")
            sink.success(payload)
        } else {
            Log.w(TAG, "EventSink is null, dropping notification from ${sbn.packageName}: $title")
        }
    }
}
