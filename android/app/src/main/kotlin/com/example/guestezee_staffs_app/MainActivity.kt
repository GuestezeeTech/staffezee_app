package com.example.guestezee_staffs_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmServicePlugin.registerWith(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        try {
                            openNotificationSettingsScreen()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        saveOrderAlertLaunchExtras(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        saveOrderAlertLaunchExtras(intent)
    }

    private fun saveOrderAlertLaunchExtras(intent: Intent?) {
        var taskId = intent?.getIntExtra(OrderAlertService.EXTRA_TASK_ID, -1) ?: -1
        var messageJson = intent?.getStringExtra(OrderAlertService.EXTRA_MESSAGE_JSON)
        if (messageJson == null) {
            Log.d("MainActivity", "Noti tap - no message_json in intent, cannot save")
            return
        }
        if (taskId < 0 && messageJson.isNotEmpty()) {
            try {
                val json = JSONObject(messageJson)
                if (json.has("task_id")) taskId = json.optInt("task_id", -1)
                else if (json.has("order_id")) taskId = json.optInt("order_id", -1)
            } catch (_: Exception) {}
        }
        if (taskId >= 0) {
            getSharedPreferences("order_alert_launch", MODE_PRIVATE)
                .edit()
                .putInt("task_id", taskId)
                .putString("message_json", messageJson)
                .apply()
            Log.d("MainActivity", "Noti tap - data stored on that noti: task_id=$taskId, message=$messageJson")
            AlarmServicePlugin.notifyOrderAlertTap()
        }
    }

    private fun openNotificationSettingsScreen() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    companion object {
        private const val APP_SETTINGS_CHANNEL = "com.guestezee.staff/app_settings"
    }
}
