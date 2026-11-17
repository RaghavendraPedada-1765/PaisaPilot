package com.raghav.paisapilot

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Reads the SMS inbox for the Dart side (channel "paisapilot/sms").
 * Messages are only handed to the app's own Dart code; nothing leaves the device.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "paisapilot/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasPermission())
                    "requestPermission" -> requestPermission(result)
                    "readInbox" -> {
                        if (!hasPermission()) {
                            result.error("NO_PERMISSION", "READ_SMS not granted", null)
                        } else {
                            val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                            io.execute {
                                try {
                                    val rows = readInbox(since)
                                    main.post { result.success(rows) }
                                } catch (e: Exception) {
                                    main.post { result.error("READ_FAILED", e.message, null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasPermission() =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) return result.success(true)
        if (pendingPermission != null) return result.error("BUSY", "Permission request in progress", null)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.READ_SMS), REQUEST_SMS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SMS) return
        pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
    }

    /** Inbox messages received after [sinceMillis], oldest first. */
    private fun readInbox(sinceMillis: Long): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(sinceMillis.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(mapOf("address" to c.getString(0), "body" to c.getString(1), "date" to c.getLong(2)))
            }
        }
        return out
    }

    companion object {
        private const val REQUEST_SMS = 4201
    }
}
