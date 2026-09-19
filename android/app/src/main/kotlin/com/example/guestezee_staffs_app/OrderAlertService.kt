package com.example.guestezee_staffs_app

import android.app.*
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.*
import androidx.core.app.NotificationCompat

class OrderAlertService : Service() {

    companion object {
        const val CHANNEL_ID = "order_alert_channel"
        const val CHANNEL_NAME = "Order Alarm"
        const val STATUS_CHANNEL_ID = "task_status_channel"
        const val STATUS_CHANNEL_NAME = "Task Status Updates"
        const val NOTIF_ID = 9911
        const val ACTION_MUTE = "com.example.guestezee_staffs_app.ACTION_MUTE"
        const val ACTION_MUTE_AND_UPDATE = "com.example.guestezee_staffs_app.ACTION_MUTE_AND_UPDATE"
        /** Escalated/Cancelled/Completed: stop loop, play alarm once ~2s, then stop service. */
        const val ACTION_SHORT_STATUS_ALERT = "com.example.guestezee_staffs_app.ACTION_SHORT_STATUS_ALERT"
        const val EXTRA_TIMEOUT_SECONDS = "timeoutSeconds"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_MESSAGE_JSON = "message_json"
        const val EXTRA_PERSIST_NOTIFICATION = "persist_notification"
    }

    private var mediaPlayer: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    private var pendingPersistNotification: Notification? = null
    private var pendingPersistNotificationId: Int = NOTIF_ID

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Stop looping alarm and tear down service (must NOT use startForegroundService for this).
        if (intent?.action == ACTION_MUTE) {
            stopAlarmSound()
            timeoutRunnable?.let { handler.removeCallbacks(it) }
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {}
            stopSelf()
            return START_NOT_STICKY
        }

        // Legacy alias – same as short status alert.
        if (intent?.action == ACTION_MUTE_AND_UPDATE ||
            intent?.action == ACTION_SHORT_STATUS_ALERT) {
            return handleShortStatusAlert(intent)
        }

        val timeoutSec = intent?.getIntExtra(EXTRA_TIMEOUT_SECONDS, 180) ?: 180
        val notifTitle = intent?.getStringExtra(EXTRA_TITLE) ?: "New Task Alert"
        val notifBody = intent?.getStringExtra(EXTRA_BODY) ?: "Ringing until you respond."
        val taskId = intent?.getIntExtra(EXTRA_TASK_ID, -1) ?: -1
        val messageJson = intent?.getStringExtra(EXTRA_MESSAGE_JSON)

        // Stop any previous notification to prevent duplicates
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.cancel(NOTIF_ID)
        } catch (e: Exception) {
            // Ignore
        }

        // Always start as foreground service for reliability (use FCM title/body)
        startForeground(NOTIF_ID, buildNotification(notifTitle, notifBody, taskId, messageJson))

        // Start alarm loop
        playLoopingAlarm()

        // Auto-stop after timeout
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = Runnable { stopSelfSafely() }
        handler.postDelayed(timeoutRunnable!!, timeoutSec * 1000L)

        return START_STICKY
    }

    private fun handleShortStatusAlert(intent: Intent?): Int {
        stopAlarmSound()
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        clearAssignedAlarmNotification()

        val timeoutSec = intent?.getIntExtra(EXTRA_TIMEOUT_SECONDS, 2) ?: 2
        val notifTitle = intent?.getStringExtra(EXTRA_TITLE) ?: "Task update"
        val notifBody = intent?.getStringExtra(EXTRA_BODY) ?: ""
        val taskId = intent?.getIntExtra(EXTRA_TASK_ID, -1) ?: -1
        val messageJson = intent?.getStringExtra(EXTRA_MESSAGE_JSON)
        val persistNotification =
            intent?.getBooleanExtra(EXTRA_PERSIST_NOTIFICATION, true) ?: true

        if (!persistNotification) {
            // FCM already posted the tray notification – play sound only.
            startForeground(NOTIF_ID, buildMinimalForegroundNotification())
            playShortAlarm()
            timeoutRunnable = Runnable { stopSelfSafely() }
            handler.postDelayed(timeoutRunnable!!, timeoutSec * 1000L)
            return START_NOT_STICKY
        }

        val notifId = statusNotificationId(taskId, notifTitle)
        val notification = buildStatusNotification(notifTitle, notifBody, taskId, messageJson)

        pendingPersistNotification = notification
        pendingPersistNotificationId = notifId

        startForeground(notifId, notification)
        playShortAlarm()

        timeoutRunnable = Runnable { stopShortAlertKeepNotification() }
        handler.postDelayed(timeoutRunnable!!, timeoutSec * 1000L)
        return START_NOT_STICKY
    }

    private fun clearAssignedAlarmNotification() {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.cancel(NOTIF_ID)
        } catch (_: Exception) {}
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
    }

    private fun playLoopingAlarm() {
        stopAlarmSound() // safety
        try {
            // Use app custom sound from res/raw/alarm.mp3 (same as FCM)
            val alarmUri = android.net.Uri.parse(
                "android.resource://${packageName}/${R.raw.alarm}"
            )

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** Single play (no loop) for Escalated / Cancelled / Completed. */
    private fun playShortAlarm() {
        stopAlarmSound()
        try {
            val alarmUri = android.net.Uri.parse(
                "android.resource://${packageName}/${R.raw.alarm}"
            )
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, alarmUri)
                isLooping = false
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAlarmSound() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    private fun stopSelfSafely() {
        stopAlarmSound()
        pendingPersistNotification = null
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
    }

    /** Stop short alert sound but keep status notification in the tray. */
    private fun stopShortAlertKeepNotification() {
        stopAlarmSound()
        pendingPersistNotification = null

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
        } catch (_: Exception) {}

        stopSelf()
    }

    private fun buildMinimalForegroundNotification(): Notification {
        return NotificationCompat.Builder(this, STATUS_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Task update")
            .setContentText("Playing alert")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setOngoing(true)
            .build()
    }

    private fun statusNotificationId(taskId: Int, title: String): Int {
        return NOTIF_ID + (if (taskId >= 0) taskId else 0) + (title.hashCode() and 0x7FFF)
    }

    private fun buildNotification(title: String, body: String, taskId: Int, messageJson: String?): Notification {
        // Explicit intent so tap opens MainActivity; pass task_id + message for navigation to task screen
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
            if (taskId >= 0) putExtra(EXTRA_TASK_ID, taskId)
            if (messageJson != null) putExtra(EXTRA_MESSAGE_JSON, messageJson)
        }

        // Use a request code that includes taskId + title hash so each notification update (e.g. Assigned -> Cancelled)
        // gets a distinct PendingIntent and tap delivers the correct extras to MainActivity.
        val requestCode = NOTIF_ID + (if (taskId >= 0) taskId else 0) + (title.hashCode() and 0x7FFF)
        val pendingLaunch = PendingIntent.getActivity(
            this,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Vibration: 0ms delay, 800ms on, 400ms off, 800ms on (then repeats via channel)
        val vibrationPattern = longArrayOf(0, 800, 400, 800)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(pendingLaunch)
            .setAutoCancel(false)
            .setVibrate(vibrationPattern)
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .build()
    }

    /** Non-ongoing notification for status updates (Escalated/Cancelled/Completed). */
    private fun buildStatusNotification(
        title: String,
        body: String,
        taskId: Int,
        messageJson: String?
    ): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
            if (taskId >= 0) putExtra(EXTRA_TASK_ID, taskId)
            if (messageJson != null) putExtra(EXTRA_MESSAGE_JSON, messageJson)
        }

        val requestCode = NOTIF_ID + (if (taskId >= 0) taskId else 0) + (title.hashCode() and 0x7FFF)
        val pendingLaunch = PendingIntent.getActivity(
            this,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, STATUS_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(false)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(Notification.CATEGORY_STATUS)
            .setContentIntent(pendingLaunch)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val customSoundUri = android.net.Uri.parse(
                "android.resource://$packageName/${R.raw.alarm}"
            )
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Assigned task notifications with custom sound"
                setSound(customSoundUri, audioAttributes)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800)
                enableLights(true)
                setBypassDnd(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val statusChannel = NotificationChannel(
                STATUS_CHANNEL_ID,
                STATUS_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Escalated, cancelled and completed task updates"
                setSound(null, null)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
                enableLights(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
            nm.createNotificationChannel(statusChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopAlarmSound()
        super.onDestroy()
    }
}

