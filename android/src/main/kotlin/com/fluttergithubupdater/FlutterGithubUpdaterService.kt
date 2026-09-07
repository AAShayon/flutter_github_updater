package com.fluttergithubupdater

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.util.Timer
import java.util.TimerTask

/**
 * Foreground service that watches the system DownloadManager finish the update
 * download and then launches the package installer automatically — so the user
 * doesn't have to keep the app open, tap a notification, or hunt for anything.
 *
 * A foreground service (not a plain manifest receiver) is required on modern
 * Android because starting the installer activity from a background receiver is
 * restricted. While this service is running the app is "in use", so launching
 * [Intent.ACTION_VIEW] is allowed. The installer still shows the normal system
 * confirm dialog, so this is never a silent install.
 */
class FlutterGithubUpdaterService : Service() {

    companion object {
        const val SERVICE_CHANNEL = "flutter_github_updater_downloading"
        const val SERVICE_NOTIFICATION_ID = 1020
        const val EXTRA_DOWNLOAD_ID = "download_id"

        /** Starts (or updates) the foreground watcher for [downloadId]. */
        fun watch(context: Context, downloadId: Long) {
            val intent = Intent(context, FlutterGithubUpdaterService::class.java)
                .putExtra(EXTRA_DOWNLOAD_ID, downloadId)
            context.startForegroundService(intent)
        }
    }

    private var downloadId = -1L
    private var watching = false
    private var finished = false
    private var pollTimer: Timer? = null

    private val completeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
            val actual = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            if (actual != downloadId) return
            if (!wasSuccessful(context, downloadId)) return
            finishAndInstall(context)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getLongExtra(EXTRA_DOWNLOAD_ID, -1L) ?: -1L
        if (id == -1L) {
            stopSelf()
            return START_NOT_STICKY
        }
        downloadId = id

        startForegroundCompat(buildNotification())

        if (!watching) {
            watching = true
            registerReceiver(
                completeReceiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
                Context.RECEIVER_NOT_EXPORTED
            )
        }

        // Broadcast may never arrive on some devices (OEM battery optimization,
        // process killed during download). Poll DownloadManager as a reliable
        // fallback so the installer still opens when the download finishes.
        startPolling()

        return START_NOT_STICKY
    }

    // Polls until the download finishes, as a reliability fallback for missed
    // ACTION_DOWNLOAD_COMPLETE broadcasts.
    private fun startPolling() {
        stopPolling()
        val timer = Timer()
        pollTimer = timer
        timer.schedule(object : TimerTask() {
            override fun run() {
                if (finished) return
                if (!wasSuccessful(this@FlutterGithubUpdaterService, downloadId)) return
                finished = true
                runOnMain {
                    setDownloadedFlag()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    launchInstaller(this@FlutterGithubUpdaterService)
                    stopPolling()
                }
            }
        }, 2000L, 2000L)
    }

    private fun stopPolling() {
        pollTimer?.cancel()
        pollTimer = null
    }

    private fun runOnMain(block: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mainExecutor.execute(block)
        } else {
            android.os.Handler(Looper.getMainLooper()).post(block)
        }
    }

    private fun finishAndInstall(context: Context) {
        if (finished) return
        finished = true
        setDownloadedFlag()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        launchInstaller(context)
        stopPolling()
    }

    private fun setDownloadedFlag() {
        getSharedPreferences(
            FlutterGithubUpdaterPlugin.PREFS, Context.MODE_PRIVATE
        ).edit()
            .putBoolean(FlutterGithubUpdaterPlugin.KEY_DOWNLOADED, true)
            .apply()
    }

    override fun onDestroy() {
        if (watching) {
            watching = false
            runCatching { unregisterReceiver(completeReceiver) }
        }
        stopPolling()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                SERVICE_NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): android.app.Notification {
        val pending = PendingIntent.getActivity(
            this, 0, Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, SERVICE_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading app update")
            .setContentText("Installing will begin automatically when ready")
            .setOngoing(true)
            .setContentIntent(pending)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                SERVICE_CHANNEL, "Update download", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Progress of in-app app updates"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun wasSuccessful(context: Context, id: Long): Boolean {
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = manager.query(DownloadManager.Query().setFilterById(id))
        var ok = false
        if (cursor != null) {
            if (cursor.moveToFirst()) {
                ok = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                ) == DownloadManager.STATUS_SUCCESSFUL
            }
            cursor.close()
        }
        return ok
    }

    private fun launchInstaller(context: Context) {
        if (!context.packageManager.canRequestPackageInstalls()) {
            // Missing install permission: no point opening an installer that
            // will be blocked. The manifest receiver's notification (or the
            // in-app check) will point the user to enable it.
            return
        }
        val file = apkFile(context)
        if (!file.exists()) return
        try {
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
            startActivity(installIntent)
        } catch (_: Exception) {
            // Fall back to the receiver's "update ready" notification.
        }
    }
}