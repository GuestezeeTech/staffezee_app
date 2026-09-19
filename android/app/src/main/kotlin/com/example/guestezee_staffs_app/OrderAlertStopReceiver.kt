package com.example.guestezee_staffs_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class OrderAlertStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        context.stopService(Intent(context, OrderAlertService::class.java))
    }
}

