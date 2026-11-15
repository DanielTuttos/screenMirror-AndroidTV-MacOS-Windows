package tv.screenmirror.receiver.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import android.app.Service
import android.os.IBinder
import tv.screenmirror.receiver.R
import tv.screenmirror.receiver.ScreenMirrorApp
import tv.screenmirror.receiver.core.ReceiverContainer
import tv.screenmirror.receiver.ui.MainActivity

/**
 * Mantiene el receptor vivo aunque la UI no esté en pantalla (24/7 en la TV).
 */
class ReceiverService : Service() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startAsForeground()
        container.runtime.start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        container.runtime.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private val container: ReceiverContainer
        get() = (application as ScreenMirrorApp).container

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Receptor",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "screenmirror.receiver"
        private const val NOTIFICATION_ID = 1
    }
}
