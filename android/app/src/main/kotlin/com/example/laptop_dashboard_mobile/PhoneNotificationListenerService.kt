package com.example.laptop_dashboard_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel

object NotificationSyncBridge {
    var eventSink: EventChannel.EventSink? = null
    var serviceInstance: PhoneNotificationListenerService? = null

    var cpu: Double = 0.0
    var ram: Double = 0.0
    var temp: Double = 0.0
    var battery: Double = 0.0
    var isPlugged: Boolean = false

    fun updateStats(
        cpu: Double,
        ram: Double,
        temp: Double,
        battery: Double,
        isPlugged: Boolean
    ) {
        this.cpu = cpu
        this.ram = ram
        this.temp = temp
        this.battery = battery
        this.isPlugged = isPlugged
        serviceInstance?.updateForegroundNotification()
    }

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
    private val CHANNEL_ID = "notification_sync_service"
    private val NOTIFICATION_ID = 1001

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Notification Sync Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps notification sync running in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val plugStatus = if (NotificationSyncBridge.isPlugged) "Charging" else "Discharging"
        val contentTitle = "Laptop: ${NotificationSyncBridge.battery.toInt()}% ($plugStatus)"
        val contentText = "CPU: ${NotificationSyncBridge.cpu.toInt()}% | RAM: ${NotificationSyncBridge.ram.toInt()}% | ${NotificationSyncBridge.temp.toInt()}°C"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(
                        "CPU: ${NotificationSyncBridge.cpu.toInt()}% | RAM: ${NotificationSyncBridge.ram.toInt()}%\n" +
                        "Temp: ${NotificationSyncBridge.temp.toInt()}°C | Battery: ${NotificationSyncBridge.battery.toInt()}% ($plugStatus)"
                    )
            )
            .build()
    }

    fun updateForegroundNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildForegroundNotification())
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        NotificationSyncBridge.serviceInstance = this
        Log.i(TAG, "NotificationListenerService connected and ready")

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        Log.i(TAG, "Started as foreground service")
    }

    override fun onDestroy() {
        NotificationSyncBridge.serviceInstance = null
        super.onDestroy()
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
