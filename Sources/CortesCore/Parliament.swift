import Foundation

/// Anything that can convene the parliament: the real Gemma 4 client or the offline demo.
/// Voices stream in one by one, so the first card shows up long before the last one is written.
public protocol Parliament: Sendable {
    func convene(events: [TranscriptEvent], mode: ConversationMode, language: AppLanguage) -> AsyncThrowingStream<ParliamentEvent, Error>
}

public enum GeminiError: LocalizedError {
    case http(Int, String)
    case emptyAnswer
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .http(429, _): return "Gemini API rate limit (429). Wait a bit or use another key."
        case .http(let code, let body): return "Gemini API error \(code): \(body.prefix(300))"
        case .emptyAnswer: return "Gemini API returned no usable voices."
        case .network(let detail): return "No connection to Gemini API: \(detail)"
        }
    }
}

/// Gemma 4 through the Gemini API `streamGenerateContent` endpoint.
/// This is the one place where the model is called.
public struct GeminiParliament: Parliament {
    public let apiKey: String
    public let model: String
    public let session: URLSession

    public static let defaultModel = "gemma-4-26b-a4b-it"

    public init(apiKey: String, model: String = GeminiParliament.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func convene(events: [TranscriptEvent], mode: ConversationMode, language: AppLanguage) -> AsyncThrowingStream<ParliamentEvent, Error> {
        // Gemma on the Gemini API may not accept systemInstruction, so the system prompt goes first in the user turn.
        let prompt = ParliamentPrompt.system(language: language) + "\n\n" + ParliamentPrompt.user(events: events, mode: mode)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var voices = try await stream(prompt, into: continuation)
                    if voices == 0 {
                        // One retry when nothing parsable came back.
                        voices = try await stream(prompt + "\n\nReturn only JSON Lines as specified.", into: continuation)
                    }
                    if voices == 0 { throw GeminiError.emptyAnswer }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A plain answer with no parliament around it: the "bare model" baseline for the eval.
    public func ask(_ prompt: String) async throws -> String {
        var text = ""
        for try await line in try await open(prompt, thinkingLevel: "minimal").lines where line.hasPrefix("data:") {
            text += Self.text(from: Data(line.dropFirst(5).utf8))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streams one answer, yields events as lines complete, returns how many voices came through.
    func stream(_ prompt: String, into continuation: AsyncThrowingStream<ParliamentEvent, Error>.Continuation) async throws -> Int {
        let bytes: URLSession.AsyncBytes
        do {
            // Gemma 4 thinks by default and can spend the whole token budget on it; "minimal" turns that off.
            bytes = try await open(prompt, thinkingLevel: "minimal")
        } catch GeminiError.http(400, let body) where body.contains("hinking") {
            bytes = try await open(prompt, thinkingLevel: nil)
        }
        var parser = ParliamentStreamParser()
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                for event in parser.feed(Self.text(from: Data(line.dropFirst(5).utf8))) { continuation.yield(event) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiError.network(error.localizedDescription)
        }
        for event in parser.finish() { continuation.yield(event) }
        return parser.voiceCount
    }

    func open(_ prompt: String, thinkingLevel: String?) async throws -> URLSession.AsyncBytes {
        do {
            return try await openOnce(prompt, thinkingLevel: thinkingLevel)
        } catch GeminiError.http(let code, _) where code >= 500 {
            // The API has occasional internal errors; one more try usually goes through.
            try await Task.sleep(nanoseconds: 700_000_000)
            return try await openOnce(prompt, thinkingLevel: thinkingLevel)
        }
    }

    func openOnce(_ prompt: String, thinkingLevel: String?) async throws -> URLSession.AsyncBytes {
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        var config: [String: Any] = ["temperature": 0.9, "maxOutputTokens": 1000]
        if let thinkingLevel { config["thinkingConfig"] = ["thinkingLevel": thinkingLevel] }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": config,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw GeminiError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw GeminiError.http(status, String(data: body, encoding: .utf8) ?? "")
        }
        return bytes
    }

    /// The answer text in one streamed chunk, without the model's thoughts.
    static func text(from data: Data) -> String {
        struct Chunk: Decodable {
            struct Candidate: Decodable { let content: Content? }
            struct Content: Decodable { let parts: [Part]? }
            struct Part: Decodable { let text: String?; let thought: Bool? }
            let candidates: [Candidate]?
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { return "" }
        return (chunk.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
    }
}

/// Offline parliament built from the canned style lines. Lets the demo run without a key or network.
public struct DemoParliament: Parliament {
    public init() {}

    public func convene(events: [TranscriptEvent], mode: ConversationMode, language: AppLanguage) -> AsyncThrowingStream<ParliamentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let situation = language == .russian ? "Тебе написали. Парламент в смятении." : "Someone wrote to you. The parliament is in turmoil."
                continuation.yield(.situation(situation))
                // Like the real parliament: at most one wild voice per answer.
                let wild = Voice.allCases.filter(\.isWild).randomElement()
                let pool = Voice.allCases.filter { !$0.isWild || $0 == wild }
                for voice in pool.shuffled().prefix(Int.random(in: 1...5)) {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { break }
                    let ex = StyleExamples.examples(voice, language)
                    continuation.yield(.voice(VoiceReply(id: voice, difficulty: ex.difficulty, passed: Bool.random(),
                                                         inner: ex.lines.randomElement()!, reply: Self.reply(voice, language))))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func reply(_ voice: Voice, _ lang: AppLanguage) -> String {
        switch (voice, lang) {
        case (.cautious, .russian): return "Давайте уточню детали и вернусь к вам до конца дня."
        case (.bold, .russian): return "Беру. Но тогда давайте сразу зафиксируем скоуп и сроки."
        case (.accountant, .russian): return "Сколько часов на это закладываем и кто их оплачивает?"
        case (.diplomat, .russian): return "Спасибо, что написали! Давайте вместе найдём удобный вариант."
        case (.cynic, .russian): return "А что из прошлого списка мы ради этого выкидываем?"
        case (.mystic, .russian): return "Давайте я подумаю до завтра и вернусь с ответом."
        case (.hedonist, .russian): return "Давайте обсудим после обеда, хорошо?"
        case (.cautious, .english): return "Let me check the details and get back to you by end of day."
        case (.bold, .english): return "I'm in. Let's lock the scope and the deadline right now."
        case (.accountant, .english): return "How many hours are we budgeting for this, and who pays for them?"
        case (.diplomat, .english): return "Thanks for reaching out! Let's find an option that works for both of us."
        case (.cynic, .english): return "And what from the old list are we dropping to make room for this?"
        case (.mystic, .english): return "Let me sleep on it and get back to you tomorrow."
        case (.hedonist, .english): return "Can we pick this up after lunch?"
        }
    }
}
