package com.example.guestezee_staffs_app

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class AlarmServicePlugin : FlutterPlugin {

    companion object {
        private const val CHANNEL_NAME = "staff/alarm_service"
        private var channel: MethodChannel? = null
        private lateinit var appContext: Context

        fun registerWith(flutterEngine: FlutterEngine) {
            if (!flutterEngine.plugins.has(AlarmServicePlugin::class.java)) {
                flutterEngine.plugins.add(AlarmServicePlugin())
            }
        }

        fun register(context: Context, messenger: BinaryMessenger) {
            setupHandlers(context, MethodChannel(messenger, CHANNEL_NAME))
        }

        private fun setupHandlers(context: Context, methodChannel: MethodChannel) {
            channel = methodChannel
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOrderAlarmService" -> {
                        val timeoutSec = call.argument<Int>("timeoutSeconds") ?: 180
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val taskId = call.argument<Int>("taskId")
                        val messageJson = call.argument<String>("messageJson")
                        val intent = Intent(context, OrderAlertService::class.java)
                            .putExtra(OrderAlertService.EXTRA_TIMEOUT_SECONDS, timeoutSec)
                        if (title != null) intent.putExtra(OrderAlertService.EXTRA_TITLE, title)
                        if (body != null) intent.putExtra(OrderAlertService.EXTRA_BODY, body)
                        if (taskId != null) intent.putExtra(OrderAlertService.EXTRA_TASK_ID, taskId)
                        if (messageJson != null) intent.putExtra(OrderAlertService.EXTRA_MESSAGE_JSON, messageJson)
                        startServiceSafely(context, intent)
                        result.success(true)
                    }
                    "muteOrderAlarmService" -> {
                        // Use startService (NOT startForegroundService): ACTION_MUTE stops
                        // the service and must not require startForeground() within 5s.
                        val intent = Intent(context, OrderAlertService::class.java).apply {
                            action = OrderAlertService.ACTION_MUTE
                        }
                        try {
                            context.startService(intent)
                        } catch (_: Exception) {
                            // Service may not be running – nothing to mute.
                        }
                        result.success(true)
                    }
                    "startShortStatusAlert" -> {
                        val timeoutSec = call.argument<Int>("timeoutSeconds") ?: 2
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val taskId = call.argument<Int>("taskId")
                        val messageJson = call.argument<String>("messageJson")
                        val intent = Intent(context, OrderAlertService::class.java).apply {
                            action = OrderAlertService.ACTION_SHORT_STATUS_ALERT
                            putExtra(OrderAlertService.EXTRA_TIMEOUT_SECONDS, timeoutSec)
                        }
                        if (title != null) intent.putExtra(OrderAlertService.EXTRA_TITLE, title)
                        if (body != null) intent.putExtra(OrderAlertService.EXTRA_BODY, body)
                        if (taskId != null) intent.putExtra(OrderAlertService.EXTRA_TASK_ID, taskId)
                        if (messageJson != null) {
                            intent.putExtra(OrderAlertService.EXTRA_MESSAGE_JSON, messageJson)
                        }
                        startServiceSafely(context, intent)
                        result.success(true)
                    }
                    "getOrderAlertLaunchExtras", "getPendingNotificationData" -> {
                        val prefs = context.getSharedPreferences("order_alert_launch", Context.MODE_PRIVATE)
                        val taskId = prefs.getInt("task_id", -1)
                        val messageJson = prefs.getString("message_json", null)
                        if (taskId >= 0 && messageJson != null) {
                            prefs.edit().remove("task_id").remove("message_json").apply()
                            result.success(mapOf("task_id" to taskId, "message" to messageJson))
                        } else {
                            result.success(null)
                        }
                    }
                    "stopOrderAlarmService" -> {
                        context.stopService(Intent(context, OrderAlertService::class.java))
                        result.success(true)
                    }
                    "clearTaskNotifications" -> {
                        // Cancel only the tapped task's status notification(s) from the
                        // tray, using the same id formula as OrderAlertService. This never
                        // touches the ongoing "Assigned" alert (NOTIF_ID) which must stay
                        // until the task is accepted.
                        val taskId = call.argument<Int>("taskId") ?: -1
                        try {
                            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                                as android.app.NotificationManager
                            val base = OrderAlertService.NOTIF_ID + (if (taskId >= 0) taskId else 0)
                            for (t in listOf("Escalated", "Cancelled", "Completed", "Task update")) {
                                val id = base + (t.hashCode() and 0x7FFF)
                                nm.cancel(id)
                                android.util.Log.d(
                                    "AlarmServicePlugin",
                                    "🧹 Notification cleared: task=$taskId title=$t id=$id"
                                )
                            }
                        } catch (e: Exception) {
                            android.util.Log.d(
                                "AlarmServicePlugin",
                                "⚠️ clearTaskNotifications failed: $e"
                            )
                        }
                        result.success(true)
                    }
                    "startIdleService" -> {
                        // Disabled (not needed for this app)
                        result.success(true)
                    }
                    "stopIdleService" -> {
                        // Disabled (not needed for this app)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun startServiceSafely(context: Context, intent: Intent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        // Called from MainActivity when the OrderAlertService notification is tapped
        fun notifyOrderAlertTap() {
            channel?.invokeMethod("orderAlertTapped", null)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        setupHandlers(appContext, methodChannel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}

