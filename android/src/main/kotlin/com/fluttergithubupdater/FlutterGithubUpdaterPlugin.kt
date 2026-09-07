package com.fluttergithubupdater

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File

/** update.apk path — matches path_provider's getExternalStorageDirectory(). */
internal fun apkFile(context: Context): File =
    File(context.getExternalFilesDir(null), FlutterGithubUpdaterPlugin.APK_NAME)

/**
 * First-party native implementation for flutter_github_updater.
 *
 * Handles the install permission flow, APK installation via FileProvider, and
 * background self-updates through the system DownloadManager (which keeps
 * downloading even if the app is killed). No app-side Kotlin required.
 */
class FlutterGithubUpdaterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        const val CHANNEL = "flutter_github_updater"
        const val APK_NAME = "update.apk"
        const val PREFS = "flutter_github_updater"
        const val KEY_ID = "download_id"
        const val KEY_TAG = "download_tag"
        const val KEY_DOWNLOADED = "downloaded"

        private fun fileProviderAuthority(context: Context): String =
            "${context.packageName}.flutter_github_updater.fileprovider"
    }

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val ch = MethodChannel(binding.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
        activity = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("NO_CONTEXT", "Plugin is not attached", null)
            return
        }
        when (call.method) {
            "canRequestPackageInstalls" -> {
                result.success(context.packageManager.canRequestPackageInstalls())
            }
            "openInstallSettings" -> {
                try {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${context.packageName}")
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
                result.success(null)
            }
            "installApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("NO_PATH", "APK path missing", null)
                    return
                }
                try {
                    val uri = FileProvider.getUriForFile(
                        context,
                        fileProviderAuthority(context),
                        File(path)
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }
            }
            "startBackgroundDownload" -> {
                startBackgroundDownload(context, call, result)
            }
            "backgroundUpdateStatus" -> {
                backgroundUpdateStatus(context, call, result)
            }
            "apkFilePath" -> {
                result.success(apkFile(context).absolutePath)
            }
            "minimizeApp" -> {
                activity?.moveTaskToBack(true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startBackgroundDownload(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val url = call.argument<String>("url")
        val tag = call.argument<String>("tag")
        if (url == null || tag == null) {
            result.error("NO_ARGS", "url and tag are required", null)
            return
        }
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val storedTag = prefs.getString(KEY_TAG, null)
            val storedId = prefs.getLong(KEY_ID, -1L)

            // Dedupe: if a download for this tag is already active (or already
            // finished), return the existing id instead of enqueuing a second
            // one — re-taps / re-prompts must never double the download.
            if (storedTag == tag && storedId != -1L) {
                val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                val cursor = manager.query(DownloadManager.Query().setFilterById(storedId))
                if (cursor != null && cursor.moveToFirst()) {
                    val status = cursor.getInt(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                    )
                    val active = status == DownloadManager.STATUS_RUNNING ||
                        status == DownloadManager.STATUS_PENDING ||
                        status == DownloadManager.STATUS_PAUSED
                    val completed = status == DownloadManager.STATUS_SUCCESSFUL
                    cursor.close()
                    if (active || completed) {
                        result.success(storedId)
                        return
                    }
                } else {
                    cursor?.close()
                }
            }

            apkFile(context).delete()

            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setTitle("App update")
                setDescription("Downloading update")
                setDestinationInExternalFilesDir(context, null, APK_NAME)
                setMimeType("application/vnd.android.package-archive")
                // Visible so the user sees real progress in the notification
                // shade without having to keep the app open. Our receiver
                // posts the actionable "Update ready" notification on finish.
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
            }
            val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val id = manager.enqueue(request)

            prefs.edit()
                .putLong(KEY_ID, id)
                .putString(KEY_TAG, tag)
                .putBoolean(KEY_DOWNLOADED, false)
                .apply()

            // Watch completion in a foreground service so the installer can be
            // opened automatically when the download finishes (background
            // activity starts are otherwise blocked on modern Android).
            try {
                FlutterGithubUpdaterService.watch(context.applicationContext, id)
            } catch (_: Exception) {
                // Service start failed — the manifest receiver + notification
                // remain as fallbacks.
            }

            result.success(id)
        } catch (e: Exception) {
            result.error("ENQUEUE_FAILED", e.message, null)
        }
    }

    private fun backgroundUpdateStatus(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val tag = call.argument<String>("tag")
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val storedTag = prefs.getString(KEY_TAG, null)
        val storedId = prefs.getLong(KEY_ID, -1L)

        var downloading = false
        var successful = false
        if (storedTag == tag && storedId != -1L) {
            val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val cursor = manager.query(DownloadManager.Query().setFilterById(storedId))
            if (cursor != null && cursor.moveToFirst()) {
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                downloading = status == DownloadManager.STATUS_RUNNING ||
                    status == DownloadManager.STATUS_PENDING ||
                    status == DownloadManager.STATUS_PAUSED
                successful = status == DownloadManager.STATUS_SUCCESSFUL
            }
            cursor?.close()
        }

        // "Downloaded" must be DERIVED FROM the DownloadManager row, not just the
        // persisted flag. The flag is only written by the completion receiver /
        // foreground service, and on many OEM devices that broadcast never
        // arrives (app process killed mid-download, battery optimizations). The
        // DownloadManager itself always knows the truth, so a finished download
        // is recognized even when the app never saw the completion broadcast.
        val downloaded = (storedTag == tag && successful) ||
            (storedTag == tag && prefs.getBoolean(KEY_DOWNLOADED, false))
        result.success(
            mapOf(
                "downloading" to downloading,
                "downloaded" to downloaded
            )
        )
    }
}