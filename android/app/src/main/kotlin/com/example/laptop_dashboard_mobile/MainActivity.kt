package com.example.laptop_dashboard_mobile

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val EVENT_CHANNEL = "laptop_dashboard_mobile/notification_events"
        const val METHOD_CHANNEL = "laptop_dashboard_mobile/notification_sync_control"
        private const val TAG = "MainActivity"
    }

    private fun requestRebindNotificationService() {
        if (NotificationSyncBridge.isNotificationAccessEnabled(this)) {
            val componentName = ComponentName(this, PhoneNotificationListenerService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                NotificationListenerService.requestRebind(componentName)
                Log.i(TAG, "Requested rebind for NotificationListenerService")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationSyncBridge.eventSink = events
                    Log.d(TAG, "EventChannel onListen called, eventSink set: ${events != null}")
                    requestRebindNotificationService()
                }

                override fun onCancel(arguments: Any?) {
                    NotificationSyncBridge.eventSink = null
                    Log.d(TAG, "EventChannel cancelled, eventSink cleared")
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessEnabled" -> {
                    result.success(NotificationSyncBridge.isNotificationAccessEnabled(this))
                }

                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
