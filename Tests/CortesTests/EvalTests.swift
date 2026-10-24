import XCTest
@testable import CortesCore

/// Runs eval/messages.json through bare Gemma 4 and through the parliament and writes eval/results-<label>.md.
/// Run with: CORTES_EVAL=1 CORTES_EVAL_LABEL=before swift test --filter EvalTests
final class EvalTests: XCTestCase {
    struct Message: Decodable { let id: String; let text: String }

    struct Row {
        let message: Message
        let bare: String
        let situation: String
        let voices: [VoiceReply]
        let firstVoice: TimeInterval
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testEval() async throws {
        let env = Env.load()
        let process = ProcessInfo.processInfo.environment
        guard process["CORTES_EVAL"] == "1", let key = env["GEMINI_API_KEY"] else {
            throw XCTSkip("Set CORTES_EVAL=1 and GEMINI_API_KEY to run")
        }
        let label = process["CORTES_EVAL_LABEL"] ?? "latest"
        let language = AppLanguage(rawValue: process["CORTES_EVAL_LANG"] ?? "ru") ?? .russian
        let messages = try JSONDecoder().decode([Message].self,
                                                from: Data(contentsOf: Self.root.appendingPathComponent("eval/messages.json")))
        let gemma = GeminiParliament(apiKey: key, model: env["GEMINI_MODEL"] ?? GeminiParliament.defaultModel)
        // CORTES_EVAL_BACKEND=local runs the parliament on Ollama; the bare-model baseline stays on the cloud.
        let parliament: Parliament = process["CORTES_EVAL_BACKEND"] == "local" ? OllamaParliament(env: env) : gemma

        var rows: [Row] = []
        for (n, message) in messages.enumerated() {
            // The free tier allows 16k input tokens a minute; two prompts per message need a pause.
            if n > 0 { try await Task.sleep(nanoseconds: UInt64(Double(process["CORTES_EVAL_PAUSE"] ?? "15")! * 1e9)) }
            // A flaky API should cost one row, not the whole run.
            let bare = (try? await gemma.ask(
                (language == .russian ? "Что ответить на это сообщение? Дай один вариант ответа.\n\n"
                                      : "What should I reply to this message? Give one reply.\n\n") + message.text))
                ?? "(request failed)"
            var situation = "", voices: [VoiceReply] = [], first: TimeInterval = -1
            let start = Date()
            do {
                for try await event in parliament.convene(events: [TranscriptEvent(speaker: "OTHER", text: message.text)],
                                                          mode: .chat, language: language) {
                    switch event {
                    case .situation(let s): situation = s
                    case .voice(let v):
                        if first < 0 { first = Date().timeIntervalSince(start) }
                        voices.append(v)
                    case .fellBack: break
                    }
                }
            } catch {
                situation = "(request failed: \(error.localizedDescription))"
            }
            rows.append(Row(message: message, bare: bare, situation: situation, voices: voices, firstVoice: first))
            print("[eval] \(message.id): \(voices.count) voices, first \(String(format: "%.1f", first)) s")
        }

        let report = Self.report(rows, label: label, language: language)
        try report.write(to: Self.root.appendingPathComponent("eval/results-\(label).md"), atomically: true, encoding: .utf8)
        print(report.components(separatedBy: "\n## ").first ?? "")
    }

    // MARK: - Metrics

    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 2 }
    }

    /// Share of a line's words that also appear in one of the style examples: high means it is copying.
    static func copyScore(_ line: String, language: AppLanguage) -> Double {
        let mine = Set(words(line))
        guard !mine.isEmpty else { return 0 }
        let examples = StyleCorpus.shared.allLines(language)
        return examples.map { Double(mine.intersection(words($0)).count) / Double(mine.count) }.max() ?? 0
    }

    static func bannedHits(_ text: String, language: AppLanguage) -> [String] {
        let lower = text.lowercased()
        return ParliamentPrompt.bannedList(language).filter { lower.contains($0) }
    }

    static func report(_ rows: [Row], label: String, language: AppLanguage) -> String {
        let voices = rows.flatMap(\.voices)
        let lines = voices.flatMap { [$0.inner, $0.reply] }
        let banned = lines.filter { !bannedHits($0, language: language).isEmpty }.count
        let copies = voices.filter { copyScore($0.inner, language: language) > 0.6 }.count
        let avgInner = Double(voices.map { words($0.inner).count }.reduce(0, +)) / Double(max(voices.count, 1))
        let avgReply = Double(voices.map { words($0.reply).count }.reduce(0, +)) / Double(max(voices.count, 1))
        let firsts = rows.map(\.firstVoice).filter { $0 >= 0 }.sorted()
        let median = firsts.isEmpty ? -1 : firsts[firsts.count / 2]
        var out = """
        # Eval: \(label)

        \(rows.count) messages, \(language.promptName), parliament on \(ProcessInfo.processInfo.environment["CORTES_EVAL_BACKEND"] == "local" ? OllamaParliament.defaultModel + " (local)" : GeminiParliament.defaultModel).

        | Metric | Value |
        |---|---|
        | Voices per message | \(String(format: "%.1f", Double(voices.count) / Double(max(rows.count, 1)))) |
        | Lines with banned phrases | \(banned) of \(lines.count) |
        | Inner lines copying an example (>60% shared words) | \(copies) of \(voices.count) |
        | Avg words: inner / reply | \(String(format: "%.1f", avgInner)) / \(String(format: "%.1f", avgReply)) |
        | First voice, median | \(String(format: "%.1f", median)) s |

        """
        for row in rows {
            out += "\n## \(row.message.id)\n\n> \(row.message.text)\n\n**Bare Gemma 4:** \(row.bare.replacingOccurrences(of: "\n", with: " "))\n\n"
            out += "**Parliament** (\(row.situation)):\n\n"
            for v in row.voices {
                let flags = bannedHits(v.inner + " " + v.reply, language: language)
                let copy = copyScore(v.inner, language: language)
                out += "- **\(v.id.name(language))** \(v.checkLabel(language)) «\(v.inner)»\n  ↳ \(v.reply)"
                if !flags.isEmpty { out += "  ⚠️ \(flags.joined(separator: ", "))" }
                if copy > 0.6 { out += "  📋 copy \(Int(copy * 100))%" }
                out += "\n"
            }
        }
        return out
    }
}
