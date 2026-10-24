import AVFoundation
import CortesCore

/// Whispers each card's inner line into your headphones, one voice after another, every voice with its own timbre:
/// ElevenLabs when there is a key and a connection, the built-in macOS voices otherwise.
@MainActor
final class Whisperer: NSObject, ObservableObject {
    enum Source: Equatable {
        case elevenLabs
        case system
    }

    /// The voice speaking right now, so its card can show it.
    @Published private(set) var speaking: Voice?
    /// The voice whose audio is still being fetched.
    @Published private(set) var loading: Voice?
    /// Which engine spoke last, so the panel can tell when ElevenLabs fell back.
    @Published private(set) var lastSource: Source?
    @Published private(set) var lastError: String?

    var isSpeaking: Bool { speaking != nil }

    /// True while this voice is fetching or speaking, so a second click does not start it again.
    func isBusy(with voice: Voice) -> Bool { loading == voice || speaking == voice }

    private let client: ElevenLabsClient?
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?
    /// Lines waiting their turn; audio for each is fetched as soon as it is queued.
    private var queue: [(voice: VoiceReply, audio: Task<Data?, Never>)] = []
    private var loop: Task<Void, Never>?
    private var language: AppLanguage = .russian
    /// Bumped on every stop. A drain loop from before a stop sees a stale value and quits without touching state,
    /// so two loops can never play at once.
    private var generation = 0

    var hasElevenLabs: Bool { client != nil }

    init(env: Env) {
        client = env["ELEVENLABS_API_KEY"] != nil ? ElevenLabsClient(env: env) : nil
        super.init()
        synthesizer.delegate = self
    }

    /// Queues a card; it is spoken after the ones before it.
    func enqueue(_ voice: VoiceReply, language: AppLanguage) {
        self.language = language
        let client = client
        let fetch = Task<Data?, Never> { [weak self] in
            guard let client else { return nil }
            do {
                return try await client.speech(for: voice.inner, voice: voice.id, language: language)
            } catch {
                // A stop cancels the fetch; that is not an ElevenLabs failure.
                if !Task.isCancelled { await MainActor.run { self?.lastError = error.localizedDescription } }
                return nil
            }
        }
        queue.append((voice, fetch))
        if loop == nil {
            let generation = generation
            loop = Task { await drain(generation) }
        }
    }

    /// Stops the current line and drops the queue.
    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        queue.forEach { $0.audio.cancel() }
        queue.removeAll()
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        resume()
        speaking = nil
        loading = nil
    }

    private func drain(_ generation: Int) async {
        while !queue.isEmpty, generation == self.generation {
            let item = queue.removeFirst()
            loading = item.voice.id
            let audio = await item.audio.value
            guard generation == self.generation else { return }
            loading = nil
            speaking = item.voice.id
            if let audio, let player = try? AVAudioPlayer(data: audio) {
                self.player = player
                player.delegate = self
                lastSource = .elevenLabs
                lastError = nil
                await withCheckedContinuation { finished = $0; player.play() }
            } else {
                await withCheckedContinuation { finished = $0; speakWithSystemVoice(item.voice) }
            }
        }
        guard generation == self.generation else { return }
        speaking = nil
        loop = nil
    }

    private func speakWithSystemVoice(_ voice: VoiceReply) {
        let utterance = AVSpeechUtterance(string: voice.inner)
        let (systemVoice, pitch) = Self.systemVoice(for: voice.id, language: language)
        utterance.voice = systemVoice
        utterance.pitchMultiplier = pitch
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 0.6
        lastSource = .system
        synthesizer.speak(utterance)
    }

    /// The macOS voices cannot whisper, so each parliament member gets a different installed voice and pitch.
    static func systemVoice(for voice: Voice, language: AppLanguage) -> (AVSpeechSynthesisVoice?, Float) {
        let prefix = language == .russian ? "ru" : "en"
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.identifier < $1.identifier }
        let index = Voice.allCases.firstIndex(of: voice)!
        let pitches: [Float] = [1.1, 0.85, 1.0, 1.2, 0.75, 0.9, 1.15]
        let chosen = installed.isEmpty ? AVSpeechSynthesisVoice(language: prefix) : installed[index % installed.count]
        return (chosen, pitches[index])
    }

    private func resume() {
        finished?.resume()
        finished = nil
    }
}

extension Whisperer: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
