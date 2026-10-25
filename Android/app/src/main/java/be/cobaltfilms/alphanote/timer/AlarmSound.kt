package be.cobaltfilms.alphanote.timer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import be.cobaltfilms.alphanote.R

/**
 * Sonnerie de fin de minuteur — mêmes fichiers que macOS (AlarmSound.swift),
 * synthétisés par scripts/make-sounds.py ; « Alarme du téléphone » reprend
 * l'alarme réglée dans Android.
 */
enum class AlarmSound(val raw: String, val label: String, val resId: Int?) {
    MINUTERIE("minuterie", "Minuterie", R.raw.alarm_minuterie),
    CLOCHE("cloche", "Cloche", R.raw.alarm_cloche),
    TELEPHONE("telephone", "Téléphone", R.raw.alarm_telephone),
    REVEIL("reveil", "Réveil", R.raw.alarm_reveil),
    ALERTE("alerte", "Alerte", R.raw.alarm_alerte),
    MONTRE("montre", "Montre", R.raw.alarm_montre),
    SONAR("sonar", "Sonar", R.raw.alarm_sonar),
    CRISTAL("cristal", "Cristal", R.raw.alarm_cristal),
    BOIS("bois", "Bois", R.raw.alarm_bois),
    PULSATION("pulsation", "Pulsation", R.raw.alarm_pulsation),
    SYSTEME("systeme", "Alarme du téléphone", null);

    fun uri(context: Context): Uri = resId
        ?.let { Uri.parse("android.resource://${context.packageName}/$it") }
        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

    companion object {
        fun fromRaw(raw: String?): AlarmSound = entries.firstOrNull { it.raw == raw } ?: MINUTERIE
    }
}

/** Joue une sonnerie sur le canal « alarme » : en boucle (minuteur) ou une fois (essai). */
class AlarmPlayer {
    private var player: MediaPlayer? = null

    fun play(context: Context, sound: AlarmSound, loop: Boolean) {
        stop()
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(context, sound.uri(context))
                isLooping = loop
                prepare()
                start()
            }
        }.getOrNull()
    }

    fun stop() {
        player?.let { runCatching { it.stop(); it.release() } }
        player = null
    }
}
