import AppKit
import CortesCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// Where the parliament runs.
    enum Backend: String, CaseIterable {
        /// Gemini API, with the local Gemma stepping in on rate limits and outages.
        case auto
        case cloud
        case local
    }

    enum Phase: Equatable {
        case idle
        case thinking
        case done
        case error(String)
    }

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var situation: String?
    /// Voices in the order they arrived, most useful first.
    @Published private(set) var voices: [VoiceReply] = []
    /// The card the user picked. The parliament never picks for them.
    @Published private(set) var chosen: Voice?
    @Published var whisperEnabled: Bool {
        didSet {
            UserDefaults.standard.set(whisperEnabled, forKey: "whisperEnabled")
            if !whisperEnabled { whisperer.stop() }
        }
    }
    /// The cloud failed and the local Gemma answered this time.
    @Published private(set) var servedLocally = false
    /// The last phrases of the call, newest last.
    @Published private(set) var heard: [TranscriptEvent] = []
    /// When the parliament will answer the other side next, while it waits out the pause between requests.
    @Published private(set) var nextAnswerAt: Date?
    @Published private(set) var stats: PickStats
    @Published var showStats = false
    @Published var showSettings = false

    // Settings, kept in UserDefaults. Keys stay in .env.
    @Published var backend: Backend { didSet { defaults.set(backend.rawValue, forKey: "backend") } }
    /// Silence that ends the other side's phrase.
    @Published var phrasePause: Double { didSet { defaults.set(phrasePause, forKey: "phrasePause") } }
    /// At most one answer per this many seconds on a call: answers stay useful and the free tier holds.
    @Published var callCooldown: Double { didSet { defaults.set(callCooldown, forKey: "callCooldown") } }
    /// Today's leading voice whispers by itself on a call.
    @Published var autoWhisperOnCalls: Bool { didSet { defaults.set(autoWhisperOnCalls, forKey: "autoWhisperOnCalls") } }
    @Published var whisperModel: String { didSet { defaults.set(whisperModel, forKey: "whisperModel") } }
    /// Off by default: the chat's text goes to the model.
    @Published var readChatHistory: Bool { didSet { defaults.set(readChatHistory, forKey: "readChatHistory") } }
    @Published var chatHistoryCount: Int { didSet { defaults.set(chatHistoryCount, forKey: "chatHistoryCount") } }
    /// Picking a card also pastes its reply into the chat's input box; Enter stays yours.
    @Published var pasteIntoChat: Bool { didSet { defaults.set(pasteIntoChat, forKey: "pasteIntoChat") } }
    /// The app you called Cortes from, where a picked reply gets pasted.
    var chatApp: NSRunningApplication?
    /// The reply pasted for the current answer, so a re-pick can replace it and an un-pick remove it.
    private var pastedReply: String?
    /// Whether Ollama runs with the local model pulled, checked when settings open.
    @Published private(set) var localAvailable: Bool?

    private let defaults = UserDefaults.standard
    private let cloud: GeminiParliament?
    private let local: OllamaParliament
    let hasElevenLabsKey: Bool
    let whisperer: Whisperer
    let listener = Listener()
    private let statsStore = PickStatsStore()
    /// The day the current answer's pick counts for, fixed at the first pick so re-picks after midnight stay put.
    private var pickDay: String?
    /// The last asked conversation, so switching language can re-run it.
    private var lastEvents: [TranscriptEvent] = []
    private var lastMode: ConversationMode = .chat
    private var task: Task<Void, Never>?

    /// How many recent phrases of a call the parliament sees.
    private let callContext = 8
    private var lastCallRequest: Date?
    private var pendingCallRequest: Task<Void, Never>?

    var ui: UIStrings { UIStrings(language) }

    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .russian
        whisperEnabled = UserDefaults.standard.object(forKey: "whisperEnabled") as? Bool ?? true
        stats = statsStore.load()
        let env = Env.load()
        whisperer = Whisperer(env: env)
        hasElevenLabsKey = env["ELEVENLABS_API_KEY"] != nil
        local = OllamaParliament(env: env)
        cloud = env["GEMINI_API_KEY"].map {
            GeminiParliament(apiKey: $0, model: env["GEMINI_MODEL"] ?? GeminiParliament.defaultModel)
        }
        let d = UserDefaults.standard
        // CORTES_BACKEND in .env is only the starting value; the settings section changes it.
        backend = Backend(rawValue: d.string(forKey: "backend") ?? env["CORTES_BACKEND"] ?? "") ?? .auto
        phrasePause = d.object(forKey: "phrasePause") as? Double ?? 1.5
        callCooldown = d.object(forKey: "callCooldown") as? Double ?? 15
        autoWhisperOnCalls = d.object(forKey: "autoWhisperOnCalls") as? Bool ?? true
        whisperModel = d.string(forKey: "whisperModel") ?? WhisperTranscriber.defaultModel
        readChatHistory = d.object(forKey: "readChatHistory") as? Bool ?? false
        chatHistoryCount = d.object(forKey: "chatHistoryCount") as? Int ?? 15
        pasteIntoChat = d.object(forKey: "pasteIntoChat") as? Bool ?? true
        listener.onPhrase = { [weak self] in self?.hear($1, from: $0) }
        listener.isMuted = { [weak self] in self?.whisperer.isSpeaking ?? false }
    }

    var hasGeminiKey: Bool { cloud != nil }

    /// No Gemini key and not running locally: canned voices.
    var isDemo: Bool { cloud == nil && backend != .local }

    var parliament: Parliament {
        switch (backend, cloud) {
        case (.local, _): return local
        case (_, nil): return DemoParliament()
        case (.cloud, let cloud?): return cloud
        case (.auto, let cloud?): return FallbackParliament(primary: cloud, fallback: local)
        }
    }

    func checkLocalModel() {
        Task { localAvailable = await local.isAvailable() }
    }

    /// Text mode: a selected message.
    /// Text mode. `history` is the last messages read from the chat window, oldest first; without a selection
    /// the parliament answers the last of them.
    func ask(_ text: String?, history: [String] = []) {
        lastEvents = history.map { TranscriptEvent(speaker: "CHAT", text: $0) }
            + (text.map { [TranscriptEvent(speaker: "OTHER", text: $0)] } ?? [])
        lastMode = .chat
        convene()
    }

    /// Call mode: the parliament answers the other side automatically, at most once per cooldown.
    /// Phrases that arrive during the pause are answered together.
    func hear(_ phrase: String, from speaker: CallSpeaker) {
        heard = Array((heard + [TranscriptEvent(speaker: speaker.rawValue, text: phrase)]).suffix(callContext))
        let wait = lastCallRequest.map { callCooldown - Date().timeIntervalSince($0) } ?? 0
        if wait <= 0 {
            answerCall()
        } else if pendingCallRequest == nil {
            nextAnswerAt = Date().addingTimeInterval(wait)
            pendingCallRequest = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
                guard !Task.isCancelled else { return }
                self?.answerCall()
            }
        }
    }

    private func answerCall() {
        pendingCallRequest = nil
        nextAnswerAt = nil
        lastCallRequest = Date()
        lastEvents = heard
        lastMode = .call
        convene()
    }

    func toggleListening() {
        if listener.isListening {
            listener.stop()
            pendingCallRequest?.cancel()
            pendingCallRequest = nil
            nextAnswerAt = nil
            heard = []
            return
        }
        Task {
            do {
                try await listener.start(language: language, pause: phrasePause, whisperModel: whisperModel)
            } catch Listener.Failure.microphoneDenied {
                show(error: ui.microphoneNeeded)
            } catch {
                show(error: ui.listeningUnavailable)
            }
        }
    }

    /// Restarts call mode so a new language or speech model takes effect.
    func restartListening() {
        guard listener.isListening else { return }
        toggleListening()
        toggleListening()
    }

    func rerunInCurrentLanguage() {
        // Recognition is tied to a language too.
        restartListening()
        guard !lastEvents.isEmpty, phase != .thinking else { return }
        convene()
    }

    func show(error message: String) {
        task?.cancel()
        phase = .error(message)
    }

    private func convene() {
        task?.cancel()
        whisperer.stop()
        phase = .thinking
        situation = nil
        voices = []
        chosen = nil
        pickDay = nil
        pastedReply = nil
        servedLocally = false
        let events = lastEvents, mode = lastMode, language = language, parliament = parliament
        // Text mode stays silent until you press ▶. On a call, today's leading voice speaks by itself.
        let speaker = mode == .call && whisperEnabled && autoWhisperOnCalls ? AutoSpeaker(leaders: todayLeaders) : nil
        task = Task {
            do {
                for try await event in parliament.convene(events: events, mode: mode, language: language) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .situation(let text):
                        situation = text
                    case .fellBack:
                        servedLocally = true
                    case .voice(let voice):
                        voices.append(voice)
                        if chosen == nil, speaker?.shouldSpeak(voice) == true { whisperer.enqueue(voice, language: language) }
                    }
                }
                guard !Task.isCancelled else { return }
                if chosen == nil, let fallback = speaker?.fallback(voices) { whisperer.enqueue(fallback, language: language) }
                phase = .done
            } catch {
                guard !Task.isCancelled else { return }
                // Voices that already arrived stay on screen.
                phase = voices.isEmpty ? .error(error.localizedDescription) : .done
            }
        }
    }

    /// Today's leading voices for the sticker on top; several when tied.
    var todayLeaders: [Voice] { PickStats.leaders(of: stats.counts(on: PickStats.dayKey(Date()))) }

    /// Picking a card makes it the winner and copies its reply; picking another one moves the win.
    /// Nothing is ever sent on the user's behalf.
    func choose(_ voice: VoiceReply) {
        if chosen == voice.id {
            // Picking the winner again takes the win back, and its text out of the chat box.
            if let day = pickDay { stats.remove(voice.id, on: day); statsStore.save(stats) }
            chosen = nil
            if let pasted = pastedReply { pastedReply = nil; unpaste(pasted) }
            return
        }
        let day = pickDay ?? PickStats.dayKey(Date())
        pickDay = day
        stats.record(voice.id, replacing: chosen, on: day)
        statsStore.save(stats)
        chosen = voice.id
        whisperer.stop()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(voice.reply, forType: .string)
        guard pasteIntoChat else { return }
        // On a call nothing was selected; the app in front of the panel is the chat.
        let app = chatApp ?? NSWorkspace.shared.frontmostApplication
        let previous = pastedReply
        pastedReply = voice.reply
        Task {
            if let previous { await ChatPaster.activate(app); ChatPaster.erase(previous) }
            await ChatPaster.paste(into: app)
        }
    }

    private func unpaste(_ text: String) {
        let app = chatApp ?? NSWorkspace.shared.frontmostApplication
        Task {
            await ChatPaster.activate(app)
            ChatPaster.erase(text)
        }
    }

    /// Whispers one card; everything else stops first, so voices never overlap.
    /// A second click while that card is still loading or speaking does nothing.
    func replay(_ voice: VoiceReply) {
        guard !whisperer.isBusy(with: voice.id) else { return }
        whisperer.stop()
        whisperer.enqueue(voice, language: language)
    }
}

/// Picks which single voice speaks by itself on a call: today's leader when it has something to say,
/// otherwise the first (most useful) voice once the answer is complete. With no picks yet, the first voice.
@MainActor
final class AutoSpeaker {
    private let leaders: [Voice]
    private var spoke = false

    init(leaders: [Voice]) { self.leaders = leaders }

    func shouldSpeak(_ voice: VoiceReply) -> Bool {
        guard !spoke, leaders.isEmpty || leaders.contains(voice.id) else { return false }
        spoke = true
        return true
    }

    func fallback(_ voices: [VoiceReply]) -> VoiceReply? {
        guard !spoke, let first = voices.first else { return nil }
        spoke = true
        return first
    }
}
