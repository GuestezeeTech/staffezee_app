package com.example.guestezee_staffs_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmServicePlugin.registerWith(flutterEngine)
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
}
