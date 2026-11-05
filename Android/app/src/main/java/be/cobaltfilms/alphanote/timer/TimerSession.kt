package be.cobaltfilms.alphanote.timer

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Duration
import java.time.ZonedDateTime
import java.util.Locale

/**
 * État d'un minuteur, indépendant de l'écran : il survit au changement de
 * note et au redémarrage (persisté par UUID de note). Port de
 * Models/TimerSession.swift.
 */
class TimerSession internal constructor(
    val id: String,
    mode: Mode,
    targetSeconds: Double,
    private val registry: TimerRegistry,
    alarmTime: Int = 7 * 3600
) {
    /** ALARM : sonne à une heure donnée (« alarm 07:30 »), pas après une durée. */
    enum class Mode(val label: String) {
        STOPWATCH("Chrono"), COUNTDOWN("Minuteur"), ALARM("Alarme");

        companion object {
            fun fromKeyword(keyword: String): Mode? {
                val lower = keyword.lowercase()
                return when {
                    lower.contains("alarm") -> ALARM
                    lower.contains("stopwatch") || lower.contains("chrono") -> STOPWATCH
                    // « pomodoro » : ancien mode, relu comme un minuteur.
                    lower.contains("countdown") || lower.contains("minuteur") || lower.contains("pomodoro") -> COUNTDOWN
                    else -> null
                }
            }

            /** Nom enregistré ; l'ancien POMODORO devient un minuteur. */
            fun fromStored(name: String): Mode = entries.firstOrNull { it.name == name } ?: COUNTDOWN
        }
    }

    enum class State { STOPPED, RUNNING, PAUSED, FINISHED }

    /** [alarmTime] : heure de l'alarme, en secondes depuis minuit. */
    data class Snapshot(
        val mode: Mode, val state: State, val targetSeconds: Double, val elapsed: Double, val runStartMillis: Long?,
        val soundPlaying: Boolean, val alarmTime: Int = 7 * 3600
    )

    private val _snapshot = MutableStateFlow(Snapshot(mode, State.STOPPED, targetSeconds, 0.0, null, false, normalizedClock(alarmTime)))
    val snapshot: StateFlow<Snapshot> = _snapshot.asStateFlow()

    private var tickJob: Job? = null
    private val alarm = AlarmPlayer()

    val mode: Mode get() = _snapshot.value.mode
    val state: State get() = _snapshot.value.state
    val targetSeconds: Double get() = _snapshot.value.targetSeconds
    val elapsed: Double get() = _snapshot.value.elapsed
    val remaining: Double get() = maxOf(0.0, targetSeconds - elapsed)
    val progress: Float get() = if (mode == Mode.STOPWATCH || targetSeconds <= 0) 0f else (elapsed / targetSeconds).coerceIn(0.0, 1.0).toFloat()
    val alarmTime: Int get() = _snapshot.value.alarmTime
    val displayTime: String get() = when (mode) {
        Mode.ALARM -> clock(alarmTime)
        Mode.STOPWATCH -> format(elapsed)
        Mode.COUNTDOWN -> format(remaining)
    }
    /** Valeur écrite dans la note : la durée, ou l'heure pour une alarme. */
    val settingSeconds: Int get() = if (mode == Mode.ALARM) alarmTime else targetSeconds.toInt()

    // ---- Commandes ----

    fun setMode(newMode: Mode) {
        if (newMode == mode) return
        val leavingAlarm = mode == Mode.ALARM
        reset()
        // La durée servait au compte à rebours jusqu'à l'alarme.
        _snapshot.value = _snapshot.value.copy(mode = newMode, targetSeconds = if (leavingAlarm) 10 * 60.0 else targetSeconds)
        persist()
    }

    /** Change l'heure de l'alarme ; armée, elle se recale sur la nouvelle heure. */
    fun setAlarmTime(secondsSinceMidnight: Int) {
        val value = normalizedClock(secondsSinceMidnight)
        _snapshot.value = if (mode == Mode.ALARM && state == State.RUNNING) {
            _snapshot.value.copy(alarmTime = value, elapsed = 0.0, runStartMillis = System.currentTimeMillis(), targetSeconds = secondsUntil(value))
        } else {
            _snapshot.value.copy(alarmTime = value)
        }
        persist()
    }

    /** Passe en alarme à cette heure et l'arme (demande en langage naturel). */
    fun arm(alarmTime: Int) {
        if (mode != Mode.ALARM) setMode(Mode.ALARM)
        reset()
        _snapshot.value = _snapshot.value.copy(alarmTime = normalizedClock(alarmTime))
        start()
    }

    fun setTargetSeconds(seconds: Double) {
        _snapshot.value = _snapshot.value.copy(targetSeconds = maxOf(1.0, seconds))
        if (state == State.RUNNING && mode != Mode.STOPWATCH && elapsed >= targetSeconds) finish()
        persist()
    }

    fun toggle() {
        when (state) {
            // Une alarme ne se met pas en pause : on la désarme.
            State.RUNNING -> if (mode == Mode.ALARM) reset() else pause()
            State.STOPPED, State.PAUSED -> start()
            State.FINISHED -> { reset(); start() }
        }
    }

    fun start() {
        if (state == State.RUNNING) return
        stopSound()
        if (mode == Mode.ALARM) _snapshot.value = _snapshot.value.copy(elapsed = 0.0, targetSeconds = secondsUntil(alarmTime))
        _snapshot.value = _snapshot.value.copy(state = State.RUNNING, runStartMillis = System.currentTimeMillis())
        scheduleTick()
        persist()
    }

    fun pause() {
        if (state != State.RUNNING) return
        syncElapsed()
        tickJob?.cancel(); tickJob = null
        _snapshot.value = _snapshot.value.copy(state = State.PAUSED, runStartMillis = null)
        persist()
    }

    fun reset() {
        tickJob?.cancel(); tickJob = null
        stopSound()
        _snapshot.value = _snapshot.value.copy(state = State.STOPPED, elapsed = 0.0, runStartMillis = null)
        persist()
    }

    fun stopSound() {
        alarm.stop()
        if (_snapshot.value.soundPlaying) _snapshot.value = _snapshot.value.copy(soundPlaying = false)
    }

    // ---- Mécanique ----

    private fun scheduleTick() {
        tickJob?.cancel()
        tickJob = registry.scope.launch {
            while (isActive) {
                delay(100)
                if (state != State.RUNNING) break
                syncElapsed()
                if (mode != Mode.STOPWATCH && elapsed >= targetSeconds) { finish(); break }
            }
        }
    }

    private fun syncElapsed() {
        val start = _snapshot.value.runStartMillis ?: return
        val now = System.currentTimeMillis()
        _snapshot.value = _snapshot.value.copy(elapsed = elapsed + (now - start) / 1000.0, runStartMillis = now)
    }

    private fun finish() {
        tickJob?.cancel(); tickJob = null
        _snapshot.value = _snapshot.value.copy(state = State.FINISHED, elapsed = targetSeconds, runStartMillis = null)
        persist()
        playSound()
    }

    private fun playSound() {
        // Hors écran, c'est la notification de TimerAlarms qui sonne.
        if (!registry.appVisible) return
        val context = registry.context ?: return
        alarm.play(context, registry.alarmSound, loop = true)
        _snapshot.value = _snapshot.value.copy(soundPlaying = true)
        vibrate(context)
    }

    private fun vibrate(context: Context) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500, 200, 500), -1))
    }

    internal fun restore(saved: Snapshot) {
        var next = saved
        if (saved.state == State.RUNNING && saved.runStartMillis != null) {
            val elapsedNow = saved.elapsed + (System.currentTimeMillis() - saved.runStartMillis) / 1000.0
            next = if (saved.mode != Mode.STOPWATCH && elapsedNow >= saved.targetSeconds) {
                saved.copy(state = State.FINISHED, elapsed = saved.targetSeconds, runStartMillis = null, soundPlaying = false)
            } else {
                saved.copy(elapsed = elapsedNow, runStartMillis = System.currentTimeMillis(), soundPlaying = false)
            }
        } else {
            next = saved.copy(soundPlaying = false)
        }
        _snapshot.value = next
        if (next.state == State.RUNNING) scheduleTick()
    }

    private fun persist() = registry.persist(this)

    companion object {
        fun format(seconds: Double): String {
            val total = seconds.toLong()
            val hours = total / 3600
            val minutes = (total % 3600) / 60
            val secs = total % 60
            return if (hours > 0) String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs)
            else String.format(Locale.US, "%02d:%02d", minutes, secs)
        }

        /** « 07:30 » pour 27 000 s depuis minuit. */
        fun clock(secondsSinceMidnight: Int): String {
            val value = normalizedClock(secondsSinceMidnight)
            return String.format(Locale.US, "%02d:%02d", value / 3600, (value % 3600) / 60)
        }

        fun normalizedClock(seconds: Int): Int {
            val day = 24 * 3600
            return ((seconds / 60 * 60) % day + day) % day
        }

        /** Délai jusqu'à la prochaine occurrence de l'heure (demain si elle est passée). */
        fun secondsUntil(secondsSinceMidnight: Int, now: ZonedDateTime = ZonedDateTime.now()): Double {
            val value = normalizedClock(secondsSinceMidnight)
            var next = now.withHour(value / 3600).withMinute((value % 3600) / 60).withSecond(0).withNano(0)
            if (!next.isAfter(now)) next = next.plusDays(1)
            return maxOf(1.0, Duration.between(now, next).toMillis() / 1000.0)
        }
    }
}

/** Une session par note (clé = UUID), restaurée depuis SharedPreferences. */
class TimerRegistry private constructor() {
    internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    internal var context: Context? = null
        private set
    private val sessions = mutableMapOf<String, TimerSession>()

    /** Sonnerie choisie dans Réglages (tenue à jour par NoteViewModel). */
    @Volatile var alarmSound: AlarmSound = AlarmSound.MINUTERIE

    /** Activité à l'écran (MainActivity onStart/onStop). */
    @Volatile var appVisible: Boolean = false

    fun stopSound(noteUUID: String) { sessions[noteUUID]?.stopSound() }

    fun attach(context: Context) { this.context = context.applicationContext }

    fun session(noteUUID: String, defaultMode: TimerSession.Mode, defaultSeconds: Int): TimerSession {
        sessions[noteUUID]?.let { return it }
        // Pour une alarme, defaultSeconds est l'heure (secondes depuis minuit).
        val session = if (defaultMode == TimerSession.Mode.ALARM) {
            TimerSession(noteUUID, defaultMode, 10 * 60.0, this, alarmTime = defaultSeconds)
        } else {
            TimerSession(noteUUID, defaultMode, defaultSeconds.toDouble(), this)
        }
        stored()[noteUUID]?.let { session.restore(it) }
        sessions[noteUUID] = session
        return session
    }

    fun discard(noteUUID: String) {
        sessions[noteUUID]?.reset()
        sessions.remove(noteUUID)
        val all = stored().toMutableMap()
        all.remove(noteUUID)
        save(all)
    }

    internal fun persist(session: TimerSession) {
        val all = stored().toMutableMap()
        all[session.id] = session.snapshot.value
        save(all)
        context?.let { TimerAlarms.update(it, session, alarmSound) }
    }

    private fun prefs() = context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun stored(): Map<String, TimerSession.Snapshot> {
        val raw = prefs()?.getString(KEY, null) ?: return emptyMap()
        return runCatching {
            val root = JSONObject(raw)
            val out = mutableMapOf<String, TimerSession.Snapshot>()
            root.keys().forEach { key ->
                val o = root.getJSONObject(key)
                out[key] = TimerSession.Snapshot(
                    mode = TimerSession.Mode.fromStored(o.getString("mode")),
                    state = TimerSession.State.valueOf(o.getString("state")),
                    targetSeconds = o.getDouble("target"),
                    elapsed = o.getDouble("elapsed"),
                    runStartMillis = if (o.isNull("runStart")) null else o.getLong("runStart"),
                    soundPlaying = false,
                    alarmTime = o.optInt("alarmTime", 7 * 3600)
                )
            }
            out
        }.getOrDefault(emptyMap())
    }

    private fun save(all: Map<String, TimerSession.Snapshot>) {
        val root = JSONObject()
        all.forEach { (key, s) ->
            root.put(key, JSONObject()
                .put("mode", s.mode.name).put("state", s.state.name)
                .put("target", s.targetSeconds).put("elapsed", s.elapsed)
                .put("runStart", s.runStartMillis ?: JSONObject.NULL)
                .put("alarmTime", s.alarmTime))
        }
        prefs()?.edit()?.putString(KEY, root.toString())?.apply()
    }

    companion object {
        val shared = TimerRegistry()
        private const val PREFS = "alphanote_timers"
        private const val KEY = "timerSessionsV1"

        /**
         * Mode et réglage lus dans le contenu d'une note timer (défaut : minuteur
         * 10 min). Pour une alarme (« alarm 07:30 »), le réglage est l'heure, en
         * secondes depuis minuit.
         */
        fun parameters(content: String): Pair<TimerSession.Mode, Int> {
            var mode = TimerSession.Mode.COUNTDOWN
            var pair: Pair<Int, Int>? = null
            for (line in content.split("\n")) {
                TimerSession.Mode.fromKeyword(line)?.let { mode = it }
                Regex("(\\d+):(\\d{1,2})").find(line)?.let { match ->
                    val first = match.groupValues[1].toIntOrNull() ?: return@let
                    val second = match.groupValues[2].toIntOrNull() ?: return@let
                    pair = first to second
                }
            }
            if (mode == TimerSession.Mode.ALARM) {
                val (hours, minutes) = pair ?: (7 to 0)
                return mode to TimerSession.normalizedClock(hours * 3600 + minutes * 60)
            }
            return mode to (pair?.let { it.first * 60 + it.second } ?: 600)
        }

        /** Ligne de réglage écrite dans la note (« countdown 4:30 », « stopwatch »). */
        fun timerLine(mode: TimerSession.Mode, seconds: Int): String = when (mode) {
            TimerSession.Mode.STOPWATCH -> "stopwatch"
            TimerSession.Mode.COUNTDOWN -> "countdown ${seconds / 60}:${"%02d".format(seconds % 60)}"
            TimerSession.Mode.ALARM -> "alarm ${TimerSession.clock(seconds)}"
        }

        /**
         * Remplace la ligne de réglage (première ligne qui commence par un mode),
         * ou l'ajoute sous l'en-tête ; le reste de la note n'est pas touché.
         * Port de NoteStore.contentWithTimerLine (macOS).
         */
        fun contentWithTimerLine(content: String, mode: TimerSession.Mode, seconds: Int): String {
            val lines = content.split("\n").toMutableList()
            val line = timerLine(mode, seconds)
            val modeWords = setOf("countdown", "stopwatch", "alarm", "alarme", "pomodoro", "minuteur", "chrono")
            val index = lines.indexOfFirst { it.trim().lowercase().split(" ").first() in modeWords }
            if (index >= 0) {
                lines[index] = line
            } else {
                val headerIndex = if (lines.firstOrNull()?.trim()?.lowercase()?.startsWith("timer") == true) 1 else 0
                lines.add(minOf(headerIndex, lines.size), line)
            }
            return lines.joinToString("\n")
        }
    }
}
