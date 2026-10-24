import Foundation

/// One voice that decided to speak. Contract between the brain and the UI; shape is fixed by the prompt.
public struct VoiceReply: Codable, Equatable, Sendable {
    public let id: Voice
    /// Skill check shown as "[Skill — Difficulty: Success]".
    public let difficulty: Difficulty
    public let passed: Bool
    /// Dramatic inner monologue addressed to the user. This is what gets whispered.
    public let inner: String
    /// What the user could actually say or send. Copied on click.
    public let reply: String

    public init(id: Voice, difficulty: Difficulty, passed: Bool, inner: String, reply: String) {
        self.id = id
        self.difficulty = difficulty
        self.passed = passed
        self.inner = inner
        self.reply = reply
    }

    public func checkLabel(_ lang: AppLanguage) -> String {
        let ui = UIStrings(lang)
        return "[\(id.skill(lang)) — \(difficulty.label(lang)): \(passed ? ui.success : ui.failure)]"
    }
}

/// What the parliament streams back: first the situation, then 1–5 voices, most useful first.
public enum ParliamentEvent: Equatable, Sendable {
    case situation(String)
    case voice(VoiceReply)
    /// The cloud failed before saying anything, so the local model is answering instead.
    case fellBack(String)
}

public enum ParliamentParseError: LocalizedError, Equatable {
    case noVoices

    public var errorDescription: String? {
        switch self {
        case .noVoices: return "The model returned no usable voices."
        }
    }
}

/// Parses the model's JSON Lines output as it streams in: one complete object per line.
/// Tolerates code fences, prose and a voice repeated twice.
public struct ParliamentStreamParser: Sendable {
    private var buffer = ""
    private var seen: Set<Voice> = []
    private var sawSituation = false

    public init() {}

    public var voiceCount: Int { seen.count }

    /// Feeds a chunk of model text, returns the events whose lines are now complete.
    public mutating func feed(_ chunk: String) -> [ParliamentEvent] {
        buffer += chunk
        var events: [ParliamentEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            if let event = parse(line: line) { events.append(event) }
        }
        return events
    }

    /// Flushes the last line, which may have no trailing newline.
    public mutating func finish() -> [ParliamentEvent] {
        let line = buffer
        buffer = ""
        return parse(line: line).map { [$0] } ?? []
    }

    private mutating func parse(line: String) -> ParliamentEvent? {
        guard let start = line.firstIndex(of: "{"), let end = line.lastIndex(of: "}"), start < end,
              let data = String(line[start...end]).data(using: .utf8) else { return nil }
        if let voice = try? JSONDecoder().decode(VoiceReply.self, from: data) {
            guard !seen.contains(voice.id), seen.count < Voice.allCases.count else { return nil }
            seen.insert(voice.id)
            return .voice(voice)
        }
        struct Situation: Decodable { let situation: String }
        if !sawSituation, let s = try? JSONDecoder().decode(Situation.self, from: data) {
            sawSituation = true
            return .situation(s.situation)
        }
        return nil
    }

    /// Parses a whole answer at once.
    public static func parseAll(_ text: String) -> [ParliamentEvent] {
        var parser = ParliamentStreamParser()
        return parser.feed(text) + parser.finish()
    }
}
