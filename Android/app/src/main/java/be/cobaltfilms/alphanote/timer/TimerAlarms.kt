package be.cobaltfilms.alphanote.timer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import androidx.core.app.NotificationCompat
import be.cobaltfilms.alphanote.MainActivity
import be.cobaltfilms.alphanote.R

/**
 * Fin de minuteur ou alarme quand l'app n'est pas à l'écran : Android peut
 * suspendre ou tuer le processus, la boucle de [TimerSession] ne sonnerait
 * pas. On programme donc l'heure de fin dans AlarmManager (setAlarmClock :
 * exacte, même en veille) ; [TimerAlarmReceiver] poste alors une notification
 * qui sonne en boucle jusqu'à ce qu'on la touche ou qu'on l'arrête. App à
 * l'écran : la session sonne elle-même. Équivalent de iOS/App/TimerNotifier.swift.
 */
object TimerAlarms {
    private const val EXTRA_NOTE = "note"
    private const val EXTRA_TITLE = "title"
    internal const val ACTION_FIRE = "be.cobaltfilms.alphanote.TIMER_FIRE"
    internal const val ACTION_STOP = "be.cobaltfilms.alphanote.TIMER_STOP"

    fun update(context: Context, session: TimerSession, sound: AlarmSound) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val fire = firePendingIntent(context, session, sound)
        manager.cancel(fire)
        val snapshot = session.snapshot.value
        if (snapshot.state != TimerSession.State.RUNNING || snapshot.mode == TimerSession.Mode.STOPWATCH) {
            if (snapshot.state != TimerSession.State.FINISHED) cancelNotification(context, session.id)
            return
        }
        val start = snapshot.runStartMillis ?: System.currentTimeMillis()
        val triggerAt = start + ((snapshot.targetSeconds - snapshot.elapsed) * 1000).toLong()
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        if (exact) {
            val show = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAt, show), fire)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, fire)
        }
    }

    fun cancelNotification(context: Context, noteUUID: String) {
        context.getSystemService(NotificationManager::class.java)?.cancel(noteUUID, NOTIFICATION_ID)
    }

    /** App revenue à l'écran : les sonneries de notification s'arrêtent. */
    fun cancelAllNotifications(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.activeNotifications.filter { it.id == NOTIFICATION_ID }.forEach { manager.cancel(it.tag, it.id) }
    }

    private fun firePendingIntent(context: Context, session: TimerSession, sound: AlarmSound): PendingIntent {
        val title = if (session.mode == TimerSession.Mode.ALARM) "Alarme ${TimerSession.clock(session.alarmTime)}" else "Minuteur terminé"
        val intent = Intent(context, TimerAlarmReceiver::class.java)
            .setAction(ACTION_FIRE)
            // Une alarme par note : l'URI distingue les PendingIntent.
            .setData(android.net.Uri.parse("alphanote-timer://${session.id}"))
            .putExtra(EXTRA_NOTE, session.id)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_SOUND, sound.raw)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    internal fun ring(context: Context, intent: Intent) {
        val noteUUID = intent.getStringExtra(EXTRA_NOTE) ?: return
        // À l'écran, la session sonne déjà.
        if (TimerRegistry.shared.appVisible) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val sound = AlarmSound.fromRaw(intent.getStringExtra(EXTRA_SOUND))
        val channelId = "timer_alarm_${sound.raw}"
        if (manager.getNotificationChannel(channelId) == null) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Minuteurs et alarmes (${sound.label})", NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(
                        sound.uri(context),
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                    )
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                }
            )
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, TimerAlarmReceiver::class.java).setAction(ACTION_STOP)
                .setData(android.net.Uri.parse("alphanote-timer://$noteUUID")).putExtra(EXTRA_NOTE, noteUUID),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "AlphaNote")
            .setContentText("AlphaNote")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setAutoCancel(true)
            .addAction(0, "Arrêter", stop)
            .build()
            // Sonne en boucle jusqu'à ce qu'on touche la notification.
            .apply { flags = flags or Notification.FLAG_INSISTENT }
        runCatching { manager.notify(noteUUID, NOTIFICATION_ID, notification) }
    }

    private const val EXTRA_SOUND = "sound"
    private const val NOTIFICATION_ID = 4207
}

class TimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            TimerAlarms.ACTION_FIRE -> TimerAlarms.ring(context, intent)
            TimerAlarms.ACTION_STOP -> intent.getStringExtra("note")?.let { note ->
                TimerAlarms.cancelNotification(context, note)
                TimerRegistry.shared.stopSound(note)
            }
        }
    }
}
