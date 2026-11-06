package be.cobaltfilms.alphanote.reminders

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import be.cobaltfilms.alphanote.MainActivity
import be.cobaltfilms.alphanote.R
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.domain.Reminder
import be.cobaltfilms.alphanote.domain.ReminderKind
import be.cobaltfilms.alphanote.domain.Reminders
import be.cobaltfilms.alphanote.timer.AlarmSound
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Rappels de notes (0.6.0). Chaque rappel du texte devient une alarme système
 * (AlarmManager.setAlarmClock, comme les minuteurs) : elle se déclenche même
 * écran éteint et app fermée. Les alarmes d'une note sont remplacées à chaque
 * sauvegarde ; elles sont reprogrammées au démarrage de l'app et après un redémarrage.
 */
object ReminderScheduler {
    private const val PREFS = "alphanote_reminders"
    internal const val ACTION_FIRE = "be.cobaltfilms.alphanote.REMINDER_FIRE"
    private const val EXTRA_NOTE = "note"
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_AT = "at"
    private const val EXTRA_KINDS = "kinds"
    private const val EXTRA_SOUND = "sound"
    private const val KEY_SOUND = "sound"

    /** Remplace les alarmes de la note par celles de [content]. Un texte vide les supprime toutes. */
    fun sync(context: Context, noteUUID: String, title: String, content: String, sound: AlarmSound) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getStringSet(key(noteUUID), emptySet()).orEmpty()
        previous.forEach { code ->
            manager.cancel(fireIntent(context, noteUUID, code.toInt(), null, null, null))
        }

        val now = LocalDateTime.now()
        val scheduled = mutableSetOf<String>()
        for (reminder in Reminders.parse(content)) {
            if (!reminder.at.isAfter(now)) continue
            val code = "$noteUUID|${reminder.at}".hashCode()
            val millis = reminder.at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val fire = fireIntent(context, noteUUID, code, title, reminder, sound)
            val show = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(millis, show), fire)
            scheduled += code.toString()
        }
        prefs.edit().putStringSet(key(noteUUID), scheduled).putString(KEY_SOUND, sound.raw).apply()
    }

    /** Reprogramme les rappels de toutes les notes (démarrage de l'app, redémarrage du téléphone). */
    suspend fun rescheduleAll(context: Context, repository: NoteRepository) {
        val sound = AlarmSound.fromRaw(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_SOUND, null))
        repository.getAllNotDeleted()
            .filter { !it.isVault && it.content.isNotBlank() && it.content.contains("rappel", ignoreCase = true) }
            .forEach { sync(context, it.uuid, it.effectiveTitle, it.content, sound) }
    }

    private fun key(noteUUID: String) = "codes_$noteUUID"

    /**
     * PendingIntent d'une alarme. Le code de requête et l'URI identifient l'alarme ;
     * les extras ne servent qu'à l'affichage quand elle sonne.
     */
    private fun fireIntent(
        context: Context, noteUUID: String, code: Int,
        title: String?, reminder: Reminder?, sound: AlarmSound?
    ): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ACTION_FIRE)
            .setData(Uri.parse("alphanote-reminder://$noteUUID/$code"))
            .putExtra(EXTRA_NOTE, noteUUID)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_AT, reminder?.at?.toString())
            .putExtra(EXTRA_KINDS, reminder?.kinds?.map { it.raw }?.toTypedArray())
            .putExtra(EXTRA_SOUND, sound?.raw)
        return PendingIntent.getBroadcast(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Affiche le rappel : notification, avec sonnerie et/ou vibration selon les natures demandées. */
    internal fun show(context: Context, intent: Intent) {
        val noteUUID = intent.getStringExtra(EXTRA_NOTE) ?: return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val kinds = intent.getStringArrayExtra(EXTRA_KINDS).orEmpty()
            .mapNotNull { ReminderKind.fromRaw(it) }.toSet()
        val sound = AlarmSound.fromRaw(intent.getStringExtra(EXTRA_SOUND))
        val channelId = channel(context, manager, kinds, sound)
        val at = intent.getStringExtra(EXTRA_AT)?.let { runCatching { LocalDateTime.parse(it) }.getOrNull() }

        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE)?.ifBlank { null } ?: "Rappel")
            .setContentText(at?.let { "Rappel de ${it.toLocalTime()}" } ?: "AlphaNote")
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(noteUUID, (noteUUID + at).hashCode(), notification) }
    }

    /**
     * Canal selon les natures : la sonnerie et la vibration sont fixées par le canal
     * (Android ne permet pas de les changer ensuite), donc un canal par combinaison.
     */
    private fun channel(context: Context, manager: NotificationManager, kinds: Set<ReminderKind>, sound: AlarmSound): String {
        val vibrate = ReminderKind.VIBRATION in kinds
        val ring = ReminderKind.SONNERIE in kinds
        val id = when {
            ring -> "rappel_sonnerie_${sound.raw}${if (vibrate) "_vib" else ""}"
            vibrate -> "rappel_vibration"
            else -> "rappel_silencieux"
        }
        if (manager.getNotificationChannel(id) != null) return id
        val channel = NotificationChannel(id, channelName(ring, vibrate, sound), NotificationManager.IMPORTANCE_HIGH)
        if (ring) {
            channel.setSound(
                sound.uri(context),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            )
        } else {
            channel.setSound(null, null)
        }
        channel.enableVibration(vibrate)
        if (vibrate) channel.vibrationPattern = longArrayOf(0, 500, 200, 500)
        manager.createNotificationChannel(channel)
        return id
    }

    private fun channelName(ring: Boolean, vibrate: Boolean, sound: AlarmSound): String = when {
        ring && vibrate -> "Rappels (${sound.label}, vibration)"
        ring -> "Rappels (${sound.label})"
        vibrate -> "Rappels (vibration)"
        else -> "Rappels (notification)"
    }
}

/** Déclenchement d'une alarme de rappel. Non exporté : seul AlarmManager l'appelle. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ReminderScheduler.ACTION_FIRE) ReminderScheduler.show(context, intent)
    }
}

/** Après un redémarrage, AlarmManager oublie tout : on reprogramme les rappels. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val pending = goAsync()
        kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                ReminderScheduler.rescheduleAll(context.applicationContext, NoteRepository(context.applicationContext))
            } finally {
                pending.finish()
            }
        }
    }
}
