import Foundation
import Speech
import AVFoundation
import Combine

/// Résultat d'un enregistrement : le fichier est déjà dans les pièces jointes
/// de la note.
struct VoiceNoteResult: Equatable {
    let noteUUID: String
    let audioName: String
    let transcript: String
    let duration: TimeInterval
}

/// Note vocale : enregistre le micro dans un fichier m4a **et** transcrit en
/// même temps (reconnaissance vocale du système, sur l'appareil quand la langue
/// le permet).
///
/// L'enregistrement est la référence : si la transcription est refusée,
/// indisponible ou s'interrompt, le fichier est gardé et `transcriptionIssue`
/// dit pourquoi le texte manque. La reconnaissance du système s'arrête d'elle-même
/// (silence, ~1 min en mode serveur) : elle est relancée par segments tant que
/// l'enregistrement dure, et les segments sont mis bout à bout.
@MainActor
final class VoiceNoteRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var transcript = ""
    /// Pourquoi il n'y a pas (ou plus) de transcription. Nil : tout va bien.
    @Published private(set) var transcriptionIssue: String?
    /// Pourquoi l'enregistrement n'a pas démarré.
    @Published private(set) var error: String?

    private let audioEngine = AVAudioEngine()
    private let sink = TapSink()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var committed: [String] = []
    private var current = ""
    private var segmentID = 0
    private var failuresInARow = 0
    private var noteUUID = ""
    private var audioName = ""
    private var segmentWaiters: [CheckedContinuation<Void, Never>] = []

    /// Démarre l'enregistrement pour la note. Faux : rien n'a démarré, voir `error`.
    @discardableResult
    func start(noteUUID: String) async -> Bool {
        guard !isRecording else { return false }
        error = nil
        transcriptionIssue = nil
        transcript = ""
        committed = []
        current = ""
        failuresInARow = 0

        guard await Self.requestMicrophone() else {
            error = "Micro non autorisé. Autorise AlphaNote dans les réglages de confidentialité."
            return false
        }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Impossible d'accéder au microphone."
            return false
        }
        #endif

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Sans micro (format nul), installTap lève une exception Objective-C.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "Aucun microphone disponible."
            return false
        }

        let name = NoteAttachments.newAudioName()
        let url = NoteAttachments.fileURL(noteUUID: noteUUID, name: name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            sink.file = try AVAudioFile(forWriting: url, settings: settings,
                                        commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        } catch {
            self.error = "Impossible de créer le fichier audio : \(error.localizedDescription)"
            return false
        }

        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.consume(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            sink.file = nil
            try? FileManager.default.removeItem(at: url)
            self.error = "Impossible de démarrer le microphone."
            return false
        }

        self.noteUUID = noteUUID
        audioName = name
        startedAt = Date()
        isRecording = true
        await startTranscription()
        return true
    }

    /// Arrête, attend la fin du segment de transcription en cours et rend le
    /// résultat. Nil : rien n'était en cours, ou l'enregistrement est trop court.
    func stop() async -> VoiceNoteResult? {
        guard isRecording else { return nil }
        isRecording = false
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        let hadRequest = sink.request != nil
        sink.request?.endAudio()
        sink.file = nil // ferme et finalise le m4a

        if hadRequest, task != nil {
            await waitForSegmentEnd(timeout: 2.5)
        }
        task?.cancel()
        task = nil
        sink.request = nil
        commitCurrent()
        releaseAudioSession()

        let url = NoteAttachments.fileURL(noteUUID: noteUUID, name: audioName)
        guard duration >= 0.7 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return VoiceNoteResult(noteUUID: noteUUID, audioName: audioName,
                               transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                               duration: duration)
    }

    /// Abandonne : le fichier est supprimé, rien n'est ajouté à la note.
    func cancel() {
        guard isRecording else { return }
        isRecording = false
        startedAt = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        sink.request?.endAudio()
        sink.request = nil
        sink.file = nil
        task?.cancel()
        task = nil
        segmentID += 1
        releaseAudioSession()
        try? FileManager.default.removeItem(at: NoteAttachments.fileURL(noteUUID: noteUUID, name: audioName))
    }

    // MARK: - Transcription

    private func startTranscription() async {
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard isRecording else { return }
        guard authorized else {
            transcriptionIssue = "Reconnaissance vocale non autorisée : l'audio est enregistré sans transcription."
            return
        }
        guard let recognizer = Self.makeRecognizer(), recognizer.isAvailable else {
            transcriptionIssue = "Transcription indisponible pour cette langue : l'audio est enregistré sans texte."
            return
        }
        self.recognizer = recognizer
        startSegment()
    }

    private func startSegment() {
        guard isRecording, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Sur l'appareil quand c'est possible : privé, et sans limite de durée.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true

        segmentID += 1
        let id = segmentID
        sink.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            let text = result?.bestTranscription.formattedString
            let finished = (result?.isFinal ?? false) || failure != nil
            Task { @MainActor in
                self?.handleSegment(id: id, text: text, finished: finished)
            }
        }
    }

    private func handleSegment(id: Int, text: String?, finished: Bool) {
        guard id == segmentID else { return }
        if let text {
            current = text
            publishTranscript()
        }
        guard finished else { return }

        let wasEmpty = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        failuresInARow = wasEmpty ? failuresInARow + 1 : 0
        commitCurrent()
        task = nil
        sink.request = nil
        let waiters = segmentWaiters
        segmentWaiters = []
        waiters.forEach { $0.resume() }

        guard isRecording else { return }
        if failuresInARow >= 8 {
            // Huit segments vides d'affilée : la reconnaissance ne répond plus.
            transcriptionIssue = "La transcription s'est interrompue : l'audio continue d'être enregistré."
            return
        }
        // Un segment vide (silence) : courte pause avant de relancer.
        let delay: UInt64 = wasEmpty ? 400_000_000 : 0
        Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            self?.startSegment()
        }
    }

    private func commitCurrent() {
        let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        current = ""
        if !text.isEmpty { committed.append(text) }
        publishTranscript()
    }

    private func publishTranscript() {
        let live = current.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = (committed + (live.isEmpty ? [] : [live])).joined(separator: " ")
    }

    private func waitForSegmentEnd(timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            segmentWaiters.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self else { return }
                // Délai dépassé : on libère l'attente, le texte partiel reste.
                let waiters = self.segmentWaiters
                self.segmentWaiters = []
                waiters.forEach { $0.resume() }
            }
        }
    }

    private func releaseAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Langue du système, sinon la même langue dans un autre pays (fr-BE →
    /// fr-FR), sinon le français.
    static func makeRecognizer() -> SFSpeechRecognizer? {
        if let exact = SFSpeechRecognizer(locale: .current) { return exact }
        let language = Locale.current.language.languageCode?.identifier ?? "fr"
        let supported = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == language }
            .sorted { $0.identifier < $1.identifier }
        if let match = supported.first, let recognizer = SFSpeechRecognizer(locale: match) { return recognizer }
        return SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    }

    private static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// Reçoit les tampons du micro sur le fil audio : les écrit dans le fichier et
/// les passe au segment de transcription du moment.
private final class TapSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _file: AVAudioFile?
    private var _request: SFSpeechAudioBufferRecognitionRequest?

    var file: AVAudioFile? {
        get { lock.withLock { _file } }
        set { lock.withLock { _file = newValue } }
    }

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let file = _file, request = _request
        lock.unlock()
        try? file?.write(from: buffer)
        request?.append(buffer)
    }
}

/// Lecture des notes vocales : une seule à la fois.
@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        guard player.play() else { return }
        self.player = player
        playingURL = url
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    /// Durée du fichier, nil s'il est absent ou illisible.
    nonisolated static func duration(of url: URL) -> TimeInterval? {
        // La vue est redessinée à chaque frappe : la durée d'un fichier n'est lue qu'une fois.
        if let known = durations.object(forKey: url as NSURL) { return known.doubleValue }
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        durations.setObject(NSNumber(value: player.duration), forKey: url as NSURL)
        return player.duration
    }

    // NSCache est sûr entre fils.
    private nonisolated(unsafe) static let durations = NSCache<NSURL, NSNumber>()

    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
