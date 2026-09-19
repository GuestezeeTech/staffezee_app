package com.example.guestezee_staffs_app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * When app is in background, the Dart FCM handler runs in a separate isolate and the
 * method channel may not start OrderAlertService. We start it from here so sound plays.
 */
class CustomFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (!isUserLoggedIn()) {
            Log.d(TAG, "User logged out – not starting alarm")
            stopOrderAlertService()
            return
        }

        // Silent token-validation push (from logout check): {"testing":true}.
        // Never start the alarm service or show anything for it.
        if (isTestNotification(remoteMessage)) {
            Log.d(TAG, "Test notification (testing:true) – ignoring")
            return
        }

        if (!isAppInForeground()) {
            val title = remoteMessage.notification?.title ?: remoteMessage.data["title"]
            val body = remoteMessage.notification?.body ?: remoteMessage.data["body"]

            // If this is Escalated, Cancelled or Completed in background: mute sound and show/update notification
            if (title != null &&
                (title.equals("Escalated", ignoreCase = true) ||
                 title.equals("Cancelled", ignoreCase = true) ||
                 title.equals("Completed", ignoreCase = true))) {
                val taskId = parseTaskId(remoteMessage)
                val messageJson = remoteMessage.data["message"] ?: if (taskId >= 0) "{\"task_id\":$taskId,\"msg\":\"\"}" else null
                val notifBody = body ?: ""
                val hasSystemNotification = remoteMessage.notification != null
                val muteUpdateIntent = Intent(this, OrderAlertService::class.java).apply {
                    action = OrderAlertService.ACTION_SHORT_STATUS_ALERT
                    putExtra(OrderAlertService.EXTRA_TIMEOUT_SECONDS, 2)
                    putExtra(OrderAlertService.EXTRA_TITLE, title)
                    putExtra(OrderAlertService.EXTRA_BODY, notifBody)
                    putExtra(
                        OrderAlertService.EXTRA_PERSIST_NOTIFICATION,
                        !hasSystemNotification
                    )
                    if (taskId >= 0) putExtra(OrderAlertService.EXTRA_TASK_ID, taskId)
                    if (messageJson != null) putExtra(OrderAlertService.EXTRA_MESSAGE_JSON, messageJson)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(muteUpdateIntent)
                } else {
                    startService(muteUpdateIntent)
                }
                Log.d(TAG, "Background: $title received, short status alert (2s)")
                return
            }

            val safeTitle = title ?: "Assigned"
            val safeBody = body ?: "Please accept the task"
            val taskId = parseTaskId(remoteMessage)
            val messageJson = remoteMessage.data["message"] ?: if (taskId >= 0) "{\"task_id\":$taskId,\"msg\":\"\"}" else null

            val intent = Intent(this, OrderAlertService::class.java)
                .putExtra(OrderAlertService.EXTRA_TIMEOUT_SECONDS, 180)
                .putExtra(OrderAlertService.EXTRA_TITLE, safeTitle)
                .putExtra(OrderAlertService.EXTRA_BODY, safeBody)
            if (taskId >= 0) intent.putExtra(OrderAlertService.EXTRA_TASK_ID, taskId)
            if (messageJson != null) intent.putExtra(OrderAlertService.EXTRA_MESSAGE_JSON, messageJson)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d(TAG, "Background: started OrderAlertService taskId=$taskId")
        }
        // When in foreground, Dart handles FCM and starts the service via method channel
    }

    private fun isTestNotification(remoteMessage: RemoteMessage): Boolean {
        val data = remoteMessage.data
        val direct = data["testing"]?.trim()?.lowercase()
        if (direct == "true" || direct == "1") return true

        val msg = data["message"] ?: return false
        // The message value can be double-encoded, e.g. "{\"testing\":true}".
        // Strip backslashes/spaces so the substring match works regardless.
        val normalized = msg.replace("\\", "").replace(" ", "").lowercase()
        return normalized.contains("\"testing\":true")
    }

    private fun parseTaskId(remoteMessage: RemoteMessage): Int {
        val data = remoteMessage.data ?: run {
            Log.d(TAG, "parseTaskId: data is null")
            return -1
        }
        var taskIdStr = data["task_id"]
        if (taskIdStr != null && taskIdStr.isNotEmpty()) {
            val id = taskIdStr.trim().toIntOrNull()
            if (id != null && id >= 0) return id
        }
        var messageStr = data["message"]
        if (messageStr == null || messageStr.isEmpty()) {
            Log.d(TAG, "parseTaskId: message key missing or empty, keys=${data.keys}")
            return -1
        }
        messageStr = messageStr.trim()
        if (messageStr.length > 2 && messageStr.startsWith("\"") && messageStr.endsWith("\"")) {
            messageStr = messageStr.substring(1, messageStr.length - 1).replace("\\\"", "\"")
        }
        try {
            val json = JSONObject(messageStr)
            if (json.has("task_id")) {
                val id = json.optInt("task_id", -1)
                if (id >= 0) {
                    Log.d(TAG, "parseTaskId: got task_id=$id from message JSON")
                    return id
                }
            }
            if (json.has("order_id")) {
                val id = json.optInt("order_id", -1)
                if (id >= 0) return id
            }
        } catch (e: Exception) {
            Log.d(TAG, "parseTaskId: JSON parse failed for message length=${messageStr.length}, e=$e")
        }
        // Fallback: match "task_id":123 or "task_id": 123 in the raw string
        val regex = "\"task_id\"\\s*:\\s*(\\d+)".toRegex()
        regex.find(messageStr)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { id ->
            if (id >= 0) {
                Log.d(TAG, "parseTaskId: got task_id=$id from regex fallback")
                return id
            }
        }
        return -1
    }

    private fun isUserLoggedIn(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.staff_is_logged_in", false)
        } catch (e: Exception) {
            false
        }
    }

    private fun stopOrderAlertService() {
        try {
            stopService(Intent(this, OrderAlertService::class.java))
        } catch (e: Exception) {
            Log.d(TAG, "stopOrderAlertService: $e")
        }
    }

    private fun isAppInForeground(): Boolean {
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val running = manager.runningAppProcesses ?: return false
            val processName = applicationContext.packageName
            for (proc in running) {
                if (proc.importance == android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                    proc.processName == processName) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    override fun onNewToken(token: String) {
        // Flutter plugin handles token; no-op here unless you need to send to server from native
    }

    companion object {
        private const val TAG = "CustomFCM"
    }
}
