import XCTest
@testable import CortesCore

/// Hits the real Gemini API. Runs only with CORTES_LIVE=1 and a key in .env.
final class LiveGeminiTests: XCTestCase {
    func testParliamentAnswersInBothLanguages() async throws {
        let env = Env.load()
        guard ProcessInfo.processInfo.environment["CORTES_LIVE"] == "1", let key = env["GEMINI_API_KEY"] else {
            throw XCTSkip("Set CORTES_LIVE=1 and GEMINI_API_KEY to run")
        }
        let parliament = GeminiParliament(apiKey: key, model: env["GEMINI_MODEL"] ?? GeminiParliament.defaultModel)
        let message = TranscriptEvent(speaker: "Client",
                                      text: "Можно маленькую правку? Нужно к понедельнику добавить экспорт в Excel, это же быстро.")
        for lang in AppLanguage.allCases {
            let start = Date()
            var first: TimeInterval?
            for try await event in parliament.convene(events: [message], mode: .chat, language: lang) {
                let t = Date().timeIntervalSince(start)
                switch event {
                case .situation(let text):
                    print("[\(lang.rawValue)] \(String(format: "%.1f", t)) s — \(text)")
                case .fellBack: break
                case .voice(let v):
                    if first == nil { first = t }
                    print("  \(String(format: "%.1f", t)) s \(v.checkLabel(lang)) \(v.inner)\n    ↳ \(v.reply)")
                }
            }
            print("[\(lang.rawValue)] first voice \(String(format: "%.1f", first ?? -1)) s, all \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        }
    }

    func testSimpleMessageGetsFewVoices() async throws {
        let env = Env.load()
        guard ProcessInfo.processInfo.environment["CORTES_LIVE"] == "1", let key = env["GEMINI_API_KEY"] else {
            throw XCTSkip("Set CORTES_LIVE=1 and GEMINI_API_KEY to run")
        }
        let parliament = GeminiParliament(apiKey: key, model: env["GEMINI_MODEL"] ?? GeminiParliament.defaultModel)
        var voices: [Voice] = []
        for try await event in parliament.convene(events: [TranscriptEvent(speaker: "Client", text: "Получили, спасибо! Всё отлично 👍")],
                                                  mode: .chat, language: .russian) {
            if case .voice(let v) = event { voices.append(v.id); print("  simple: \(v.id.rawValue) — \(v.inner)") }
        }
        print("[simple] \(voices.count) voices")
        XCTAssertLessThanOrEqual(voices.count, 3)
    }

    /// Prints how many input tokens one parliament prompt costs, to plan around the free tier's per-minute limit.
    func testPromptTokenCount() async throws {
        let env = Env.load()
        guard ProcessInfo.processInfo.environment["CORTES_LIVE"] == "1", let key = env["GEMINI_API_KEY"] else {
            throw XCTSkip("Set CORTES_LIVE=1 and GEMINI_API_KEY to run")
        }
        let prompt = ParliamentPrompt.system(language: .russian) + "\n\n"
            + ParliamentPrompt.user(events: [TranscriptEvent(speaker: "OTHER", text: "Созвонимся сегодня?")], mode: .chat)
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiParliament.defaultModel):countTokens")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": prompt]]]]])
        let (data, _) = try await URLSession.shared.data(for: request)
        print("[tokens] \(String(data: data, encoding: .utf8) ?? "")")
    }

    func testElevenLabsSpeaksBothLanguages() async throws {
        let env = Env.load()
        guard ProcessInfo.processInfo.environment["CORTES_LIVE"] == "1", let key = env["ELEVENLABS_API_KEY"] else {
            throw XCTSkip("Set CORTES_LIVE=1 and ELEVENLABS_API_KEY to run")
        }
        _ = key
        let client = ElevenLabsClient(env: env)
        for (lang, text) in [(AppLanguage.russian, "Ты слышишь это? Это звук скоупа."), (.english, "Do you hear that?")] {
            for voice in Voice.allCases {
                let start = Date()
                let audio = try await client.speech(for: text, voice: voice, language: lang)
                print("[tts \(lang.rawValue) \(voice.rawValue)] \(String(format: "%.1f", Date().timeIntervalSince(start))) s, \(audio.count) bytes")
                XCTAssertGreaterThan(audio.count, 1000)
            }
        }
    }
}
