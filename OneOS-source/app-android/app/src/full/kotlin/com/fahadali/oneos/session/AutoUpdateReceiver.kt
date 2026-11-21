package com.fahadali.oneos.session

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Checks the owner's release feed twice a day and lets the verified root path self-update. */
class AutoUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        schedule(context)
        AppUpdater.check(context.applicationContext, force = true, autoInstall = true)
    }

    companion object {
        private const val INTERVAL = 12L * 60L * 60L * 1000L

        private fun operation(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            732,
            Intent(context, AutoUpdateReceiver::class.java).setAction("com.fahadali.oneos.AUTO_UPDATE"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun schedule(context: Context) {
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 60_000L,
                INTERVAL,
                operation(context),
            )
        }
    }
}
