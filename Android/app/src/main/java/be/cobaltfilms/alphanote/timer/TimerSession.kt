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
    private val registry: TimerRegistry
) {
    enum class Mode(val label: String) {
        STOPWATCH("Chrono"), COUNTDOWN("Minuteur"), POMODORO("Pomodoro");

        companion object {
            fun fromKeyword(keyword: String): Mode? {
                val lower = keyword.lowercase()
                return when {
                    lower.contains("pomodoro") -> POMODORO
                    lower.contains("stopwatch") || lower.contains("chrono") -> STOPWATCH
                    lower.contains("countdown") || lower.contains("minuteur") -> COUNTDOWN
                    else -> null
                }
            }
        }
    }

    enum class State { STOPPED, RUNNING, PAUSED, FINISHED }

    data class Snapshot(val mode: Mode, val state: State, val targetSeconds: Double, val elapsed: Double, val runStartMillis: Long?, val soundPlaying: Boolean)

    private val _snapshot = MutableStateFlow(Snapshot(mode, State.STOPPED, targetSeconds, 0.0, null, false))
    val snapshot: StateFlow<Snapshot> = _snapshot.asStateFlow()

    private var tickJob: Job? = null
    private val alarm = AlarmPlayer()

    val mode: Mode get() = _snapshot.value.mode
    val state: State get() = _snapshot.value.state
    val targetSeconds: Double get() = _snapshot.value.targetSeconds
    val elapsed: Double get() = _snapshot.value.elapsed
    val remaining: Double get() = maxOf(0.0, targetSeconds - elapsed)
    val progress: Float get() = if (mode == Mode.STOPWATCH || targetSeconds <= 0) 0f else (elapsed / targetSeconds).coerceIn(0.0, 1.0).toFloat()
    val displayTime: String get() = format(if (mode == Mode.STOPWATCH) elapsed else remaining)

    // ---- Commandes ----

    fun setMode(newMode: Mode) {
        if (newMode == mode) return
        reset()
        _snapshot.value = _snapshot.value.copy(mode = newMode, targetSeconds = if (newMode == Mode.POMODORO) 25 * 60.0 else targetSeconds)
        persist()
    }

    fun setTargetSeconds(seconds: Double) {
        _snapshot.value = _snapshot.value.copy(targetSeconds = maxOf(1.0, seconds))
        if (state == State.RUNNING && mode != Mode.STOPWATCH && elapsed >= targetSeconds) finish()
        persist()
    }

    fun toggle() {
        when (state) {
            State.RUNNING -> pause()
            State.STOPPED, State.PAUSED -> start()
            State.FINISHED -> { reset(); start() }
        }
    }

    fun start() {
        if (state == State.RUNNING) return
        stopSound()
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

    fun attach(context: Context) { this.context = context.applicationContext }

    fun session(noteUUID: String, defaultMode: TimerSession.Mode, defaultSeconds: Int): TimerSession {
        sessions[noteUUID]?.let { return it }
        val session = TimerSession(noteUUID, defaultMode, defaultSeconds.toDouble(), this)
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
                    mode = TimerSession.Mode.valueOf(o.getString("mode")),
                    state = TimerSession.State.valueOf(o.getString("state")),
                    targetSeconds = o.getDouble("target"),
                    elapsed = o.getDouble("elapsed"),
                    runStartMillis = if (o.isNull("runStart")) null else o.getLong("runStart"),
                    soundPlaying = false
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
                .put("runStart", s.runStartMillis ?: JSONObject.NULL))
        }
        prefs()?.edit()?.putString(KEY, root.toString())?.apply()
    }

    companion object {
        val shared = TimerRegistry()
        private const val PREFS = "alphanote_timers"
        private const val KEY = "timerSessionsV1"

        /** Mode et durée lus dans le contenu d'une note timer (défaut : minuteur 10 min). */
        fun parameters(content: String): Pair<TimerSession.Mode, Int> {
            var mode = TimerSession.Mode.COUNTDOWN
            var seconds = 600
            for (line in content.split("\n")) {
                TimerSession.Mode.fromKeyword(line)?.let { mode = it }
                Regex("(\\d+):(\\d{1,2})").find(line)?.let { match ->
                    val minutes = match.groupValues[1].toIntOrNull() ?: return@let
                    val secs = match.groupValues[2].toIntOrNull() ?: return@let
                    seconds = minutes * 60 + secs
                }
            }
            return mode to seconds
        }

        /** Ligne de réglage écrite dans la note (« countdown 4:30 », « stopwatch »). */
        fun timerLine(mode: TimerSession.Mode, seconds: Int): String = when (mode) {
            TimerSession.Mode.STOPWATCH -> "stopwatch"
            TimerSession.Mode.COUNTDOWN -> "countdown ${seconds / 60}:${"%02d".format(seconds % 60)}"
            TimerSession.Mode.POMODORO -> "pomodoro ${seconds / 60}:${"%02d".format(seconds % 60)}"
        }

        /**
         * Remplace la ligne de réglage (première ligne qui commence par un mode),
         * ou l'ajoute sous l'en-tête ; le reste de la note n'est pas touché.
         * Port de NoteStore.contentWithTimerLine (macOS).
         */
        fun contentWithTimerLine(content: String, mode: TimerSession.Mode, seconds: Int): String {
            val lines = content.split("\n").toMutableList()
            val line = timerLine(mode, seconds)
            val modeWords = setOf("countdown", "stopwatch", "pomodoro", "minuteur", "chrono")
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
