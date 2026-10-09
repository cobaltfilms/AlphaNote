import Foundation
import Speech
import AVFoundation
import Combine

enum SpeechRecognizerError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case audioEngineFailedToStart
    case recognitionFailed(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reconnaissance vocale non autorisée. Veuillez activer l'accès dans les préférences système."
        case .notAvailable:
            return "La reconnaissance vocale n'est pas disponible sur cet appareil."
        case .audioEngineFailedToStart:
            return "Impossible d'accéder au microphone."
        case .recognitionFailed(let message):
            return "Erreur de reconnaissance: \(message)"
        case .unknown:
            return "Une erreur inconnue s'est produite."
        }
    }
}

#if os(macOS)
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var error: SpeechRecognizerError?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: DispatchSourceTimer?
    private let silenceQueue = DispatchQueue(label: "com.alphanote.speech.silence")
    private let silenceThreshold: TimeInterval = 3.0

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() async throws {
        guard !isListening else { return }

        error = nil
        transcript = ""

        guard await requestAuthorization() else {
            error = .notAuthorized
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = .notAvailable
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            self.error = .unknown
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            self.error = .audioEngineFailedToStart
            return
        }

        isListening = true
        resetSilenceTimer()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, recognitionError in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if recognitionError != nil {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }

        silenceTimer?.cancel()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: silenceQueue)
        timer.schedule(deadline: .now() + silenceThreshold)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if !self.transcript.isEmpty {
                    self.stopListening()
                }
            }
        }
        silenceTimer = timer
        timer.resume()
    }
}
#else
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var error: SpeechRecognizerError?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: DispatchSourceTimer?
    private let silenceQueue = DispatchQueue(label: "com.alphanote.speech.silence")
    private let silenceThreshold: TimeInterval = 3.0

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() async throws {
        guard !isListening else { return }

        error = nil
        transcript = ""

        guard await requestAuthorization() else {
            error = .notAuthorized
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = .notAvailable
            return
        }

        let audioSession: AVAudioSession
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = .audioEngineFailedToStart
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            self.error = .unknown
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            self.error = .audioEngineFailedToStart
            return
        }

        isListening = true
        resetSilenceTimer()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, recognitionError in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if recognitionError != nil {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }

        silenceTimer?.cancel()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: silenceQueue)
        timer.schedule(deadline: .now() + silenceThreshold)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if !self.transcript.isEmpty {
                    self.stopListening()
                }
            }
        }
        silenceTimer = timer
        timer.resume()
    }
}
#endif
