package com.delamate.chat

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log

class DelamateApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            createCallNotificationChannel()
        } catch (e: Exception) {
            // Never crash the app because of notification channel setup.
            Log.e("DelamateApp", "Failed to create call notification channel", e)
        }
    }

    private fun createCallNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channelId = "delamate_call_v2"

        if (manager.getNotificationChannel(channelId) != null) return

        val ringtoneUri: Uri =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val channel = NotificationChannel(
            channelId,
            "Incoming Calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming call alerts with ringtone"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 700, 700)
            setSound(
                ringtoneUri,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableLights(true)
        }

        manager.createNotificationChannel(channel)
    }
}
