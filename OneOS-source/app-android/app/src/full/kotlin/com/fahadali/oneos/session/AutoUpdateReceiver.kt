package com.fahadali.oneos.session

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Checks the owner's release feed twice a day and lets the verified root path self-update. */
class AutoUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            schedule(context, force = true)
        }
        AppUpdater.check(context.applicationContext, force = true, autoInstall = true)
    }

    companion object {
        private const val ACTION_AUTO_UPDATE = "com.fahadali.oneos.AUTO_UPDATE"
        private const val INITIAL_DELAY = 15L * 60L * 1000L
        private const val INTERVAL = 12L * 60L * 60L * 1000L

        private fun updateIntent(context: Context): Intent =
            Intent(context, AutoUpdateReceiver::class.java).setAction(ACTION_AUTO_UPDATE)

        private fun operation(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            732,
            updateIntent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun schedule(context: Context, force: Boolean = false) {
            if (!force) {
                val existing = PendingIntent.getBroadcast(
                    context,
                    732,
                    updateIntent(context),
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                )
                if (existing != null) return
            }
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + INITIAL_DELAY,
                INTERVAL,
                operation(context),
            )
        }
    }
}
