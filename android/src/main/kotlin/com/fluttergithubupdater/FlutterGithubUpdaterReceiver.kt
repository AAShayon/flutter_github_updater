package com.fluttergithubupdater

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider

/**
 * Listens for the system DownloadManager finishing the background update and
 * posts an "update ready" notification. Tapping it launches the package
 * installer directly — no app code involved, so it survives app restarts.
 */
class FlutterGithubUpdaterReceiver : BroadcastReceiver() {

    companion object {
        const val UPDATE_CHANNEL = "flutter_github_updater_updates"
        const val NOTIFICATION_ID = 1010
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return

        val prefs = context.getSharedPreferences(
            FlutterGithubUpdaterPlugin.PREFS, Context.MODE_PRIVATE
        )
        val expectedId = prefs.getLong(FlutterGithubUpdaterPlugin.KEY_ID, -1L)
        val actualId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (actualId != expectedId) return

        var successful = false
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = manager.query(DownloadManager.Query().setFilterById(actualId))
        if (cursor != null && cursor.moveToFirst()) {
            successful = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            ) == DownloadManager.STATUS_SUCCESSFUL
        }
        cursor?.close()
        if (!successful) return

        prefs.edit().putBoolean(FlutterGithubUpdaterPlugin.KEY_DOWNLOADED, true).apply()
        notifyReady(context)
    }

    private fun notifyReady(context: Context) {
        val file = apkFile(context)
        if (!file.exists()) return

        createChannel(context)
        val notify = NotificationManagerCompat.from(context)
        if (!notify.areNotificationsEnabled()) return

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.flutter_github_updater.fileprovider",
            file
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val pending = PendingIntent.getActivity(
            context, 0, installIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, UPDATE_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("App update ready")
            .setContentText("Tap to install the new version")
            .setStyle(NotificationCompat.BigTextStyle().bigText("A new version of the app has been downloaded. Tap to install it."))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        notify.notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel(context: Context) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                UPDATE_CHANNEL, "App updates", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Background app update status" }
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }
}