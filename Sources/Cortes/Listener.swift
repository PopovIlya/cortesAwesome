import AVFoundation
import CortesCore
import os
import ScreenCaptureKit

/// Who said a phrase on a call.
enum CallSpeaker: String {
    /// The other side, through the system audio playing in your headphones.
    case them = "THEM"
    /// Microphone only, when system audio is not available: anyone in the room.
    case anyone = "SPEAKER"
}

/// Listens to the other side of a call through the system audio in your headphones.
/// Only when that is not available does it fall back to the microphone, which hears everyone.
/// Phrases end on a pause and are recognised by Whisper on this Mac.
@MainActor
final class Listener: ObservableObject {
    enum Failure: Error {
        case microphoneDenied
        case unavailable
    }

    enum ModelState: Equatable {
        case idle
        /// Downloading the model, with the completed fraction.
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var isListening = false
    /// False when system audio could not be captured and the microphone stands in.
    @Published private(set) var hearsOtherSide = false
    /// Someone is talking right now; the phrase is not finished yet.
    @Published private(set) var hearsSpeech = false
    /// A finished phrase is being recognised.
    @Published private(set) var transcribing = false
    @Published private(set) var model: ModelState = .idle

    /// Called with each recognised phrase.
    var onPhrase: ((CallSpeaker, String) -> Void)?
    /// While this returns true, what the mic hears is dropped, so the parliament does not answer its own whisper.
    var isMuted: () -> Bool = { false }

    private let log = Logger(subsystem: "ai.cortes.parliament", category: "call")
    private let engine = AVAudioEngine()
    private var capture: SystemAudioCapture?
    private var transcriber: WhisperTranscriber?
    private var segmenter = PhraseSegmenter()
    private var speaker: CallSpeaker = .them
    private var language: AppLanguage = .russian

    func start(language: AppLanguage, pause: TimeInterval, whisperModel: String) async throws {
        guard !isListening else { return }
        self.language = language
        segmenter = PhraseSegmenter(pause: pause)
        let transcriber = WhisperTranscriber(model: whisperModel)
        self.transcriber = transcriber
        loadModel(transcriber)

        // The other side: system audio, without Cortes' own whisper. Needs Screen & System Audio Recording.
        let capture = SystemAudioCapture()
        capture.onSample = { [weak self] sample in
            let samples = AudioSamples.floats(from: sample)
            Task { @MainActor in self?.append(samples) }
        }
        do {
            try await capture.start()
            self.capture = capture
            speaker = .them
            hearsOtherSide = true
            log.info("listening to system audio")
        } catch {
            log.error("system audio unavailable, falling back to the microphone: \(error.localizedDescription, privacy: .public)")
            try await startMicrophone()
            speaker = .anyone
            hearsOtherSide = false
        }
        isListening = true
    }

    /// The model downloads on first use (hundreds of MB), so it starts loading as soon as listening does.
    private func loadModel(_ transcriber: WhisperTranscriber) {
        model = .loading
        Task {
            do {
                _ = try await transcriber.load { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.model != .ready else { return }
                        self.model = fraction < 1 ? .downloading(fraction) : .loading
                    }
                }
                model = .ready
            } catch {
                log.error("whisper model failed: \(error.localizedDescription, privacy: .public)")
                model = .failed(error.localizedDescription)
            }
        }
    }

    private func startMicrophone() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.microphoneDenied }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            let samples = AudioSamples.floats(from: buffer)
            Task { @MainActor in self?.append(samples) }
        }
        engine.prepare()
        try engine.start()
    }

    private func append(_ samples: [Float]) {
        guard isListening else { return }
        // Only the mic can pick up the whisper; system audio excludes Cortes' own sound.
        if speaker == .anyone && isMuted() { return }
        let phrases = segmenter.feed(samples)
        if hearsSpeech != segmenter.isSpeaking { hearsSpeech = segmenter.isSpeaking }
        for phrase in phrases { recognise(phrase) }
    }

    private func recognise(_ samples: [Float]) {
        guard let transcriber else { return }
        let speaker = speaker, language = language
        transcribing = true
        Task {
            defer { transcribing = false }
            do {
                let text = try await transcriber.transcribe(samples, language: language)
                guard isListening, Self.isSpeech(text) else { return }
                log.info("phrase from \(speaker.rawValue, privacy: .public), \(text.count) chars")
                onPhrase?(speaker, text)
            } catch {
                log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Whisper sometimes "hears" stock phrases in noise; those are not the other side talking.
    static func isSpeech(_ text: String) -> Bool {
        let lower = text.lowercased()
        let stock = ["продолжение следует", "субтитры", "редактор субтитров", "спасибо за просмотр",
                     "thank you for watching", "thanks for watching", "[music]", "[музыка]"]
        return text.count > 3 && !stock.contains { lower.contains($0) }
    }

    /// Takes effect on the next phrase, without restarting.
    func setPause(_ pause: TimeInterval) { segmenter.pause = pause }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        capture?.stop()
        capture = nil
        transcriber = nil
        isListening = false
        hearsSpeech = false
        transcribing = false
    }
}

/// Captures what the Mac is playing (the other side of the call in your headphones) through ScreenCaptureKit.
/// Cortes' own audio is excluded, so the parliament never hears its own whisper.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onSample: ((CMSampleBuffer) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "cortes.system-audio")
    private let log = Logger(subsystem: "ai.cortes.parliament", category: "capture")
    private var samples = 0

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            log.error("no displays to capture from; is Screen & System Audio Recording allowed for this build?")
            throw Listener.Failure.unavailable
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        // Only the audio matters; keep the video side as small and rare as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: config, delegate: self)
        // A screen output must exist, or the stream complains about every frame; frames are dropped below.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        samples += 1
        if samples == 1 || samples % 500 == 0 { log.info("audio buffers received: \(self.samples)") }
        onSample?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("system audio stopped: \(error.localizedDescription, privacy: .public)")
    }
}
