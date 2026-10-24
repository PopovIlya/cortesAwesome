import Foundation

/// Gemma 4 running on this Mac through Ollama. No rate limit, no network, nothing leaves the machine.
public struct OllamaParliament: Parliament {
    public let model: String
    public let host: URL
    public let session: URLSession
    /// The style examples are drawn once per launch, so the system prompt stays the same between calls
    /// and Ollama can reuse its cache instead of reading 2,000 tokens every time.
    let seed: UInt64

    public static let defaultModel = "gemma4:e4b"
    public static let defaultHost = URL(string: "http://localhost:11434")!

    public init(model: String = OllamaParliament.defaultModel, host: URL = OllamaParliament.defaultHost,
                session: URLSession = .shared, seed: UInt64 = .random(in: 0...UInt64.max)) {
        self.model = model
        self.host = host
        self.session = session
        self.seed = seed
    }

    public init(env: Env) {
        self.init(model: env["OLLAMA_MODEL"] ?? Self.defaultModel,
                  host: env["OLLAMA_HOST"].flatMap(URL.init(string:)) ?? Self.defaultHost)
    }

    /// True when Ollama answers and has the model pulled.
    public func isAvailable() async -> Bool {
        var request = URLRequest(url: host.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        return (try? JSONDecoder().decode(Tags.self, from: data))?.models.contains { $0.name == model } ?? false
    }

    public func convene(events: [TranscriptEvent], mode: ConversationMode, language: AppLanguage) -> AsyncThrowingStream<ParliamentEvent, Error> {
        var rng = SeededGenerator(seed: seed ^ (language == .russian ? 1 : 2))
        let system = ParliamentPrompt.system(language: language, using: &rng)
        let user = ParliamentPrompt.user(events: events, mode: mode)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: host.appendingPathComponent("api/chat"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
                        "stream": true,
                        "think": false,
                        "keep_alive": "30m",
                        "options": ["temperature": 0.9, "num_ctx": 4096, "num_predict": 700],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw GeminiError.http(status, "Ollama") }

                    struct Chunk: Decodable { struct Message: Decodable { let content: String? }; let message: Message? }
                    var parser = ParliamentStreamParser()
                    for try await line in bytes.lines {
                        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
                        for event in parser.feed(chunk.message?.content ?? "") { continuation.yield(event) }
                    }
                    for event in parser.finish() { continuation.yield(event) }
                    if parser.voiceCount == 0 { throw GeminiError.emptyAnswer }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Tries the cloud first and switches to the local model when the cloud is rate-limited or unreachable,
/// as long as nothing has been shown yet.
public struct FallbackParliament: Parliament {
    public let primary: Parliament
    public let fallback: Parliament

    public init(primary: Parliament, fallback: Parliament) {
        self.primary = primary
        self.fallback = fallback
    }

    static func shouldFallBack(_ error: Error) -> Bool {
        switch error {
        case GeminiError.http(let code, _): return code == 429 || code >= 500
        case GeminiError.network: return true
        default: return false
        }
    }

    public func convene(events: [TranscriptEvent], mode: ConversationMode, language: AppLanguage) -> AsyncThrowingStream<ParliamentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var yielded = false
                do {
                    for try await event in primary.convene(events: events, mode: mode, language: language) {
                        yielded = true
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch where !yielded && Self.shouldFallBack(error) && !Task.isCancelled {
                    let cloudError = error
                    continuation.yield(.fellBack(error.localizedDescription))
                    do {
                        for try await event in fallback.convene(events: events, mode: mode, language: language) {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch is URLError {
                        // Ollama is not running: the cloud's failure is the one worth showing.
                        continuation.finish(throwing: cloudError)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// SplitMix64: a tiny deterministic generator, so a seed always draws the same style examples.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
