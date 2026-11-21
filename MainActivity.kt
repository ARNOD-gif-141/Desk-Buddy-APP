package com.arnod.arno_link

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {
    private var nid = 100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arno/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "media" -> {
                    val code = when (call.argument<String>("key")) {
                        "pp" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> 0
                    }
                    if (code != 0) {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                    }
                    result.success(true)
                }
                "notify" -> {
                    val title = call.argument<String>("title") ?: "Desk Buddy"
                    val body = call.argument<String>("body") ?: ""
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val b: Notification.Builder
                    if (Build.VERSION.SDK_INT >= 26) {
                        val ch = NotificationChannel("arno_buddy", "Desk Buddy", NotificationManager.IMPORTANCE_HIGH)
                        nm.createNotificationChannel(ch)
                        b = Notification.Builder(this, "arno_buddy")
                    } else {
                        b = Notification.Builder(this)
                    }
                    b.setSmallIcon(applicationInfo.icon).setContentTitle(title).setContentText(body)
                        .setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true)
                    nm.notify(nid++, b.build())
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
